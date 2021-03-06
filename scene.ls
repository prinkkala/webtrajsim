Cannon = require 'cannon'
{Signal} = require './signal.ls'
jStat = require 'jstat'
P = require 'bluebird'
Co = P.coroutine
seqr = require './seqr.ls'
{loadCollada, mergeObject} = require './utils.ls'

perlin = require './vendor/perlin.js'

# Todo: ugly
window.THREE = THREE = require 'three'
require './three.js/examples/js/SkyShader.js'

# TODO: Find a good fidelity/performance
# compromise parameters
export class Scene
	({@minStepDuration=1/60, @camera, @visual, @physics}={}) ->
		@ <<<
			beforePhysics: new Signal
			onPhysics: new Signal
			afterPhysics: new Signal

			beforeRender: new Signal
			onRender: new Signal
			afterRender: new Signal

			onTickHandled: new Signal

			onStart: new Signal
			onExit: new Signal

		@physics ?= new Cannon.World
			..gravity.set 0, -9.81, 0
			..defaultContactMaterial
				..friction = 0.7
				..restitution = 0.3
			..solver.iterations = 100
			..broadphase = new Cannon.SAPBroadphase @physics
		/*@physics =
			add: ->
			removeBody: ->
			addEventListener: ->
			step: ->
			bodies: []*/

		@visual ?= new THREE.Scene
		aspect = screen.width / screen.height
		@camera ?= new THREE.PerspectiveCamera 70/aspect, 1, 0.01, 450000

		@time = 0

		@onPhysics.add (dt) ~>
			nSteps = Math.ceil dt/@minStepDuration
			stepdur = dt/nSteps
			@physics.step stepdur, dt, nSteps

	tick: (dt) ->
		if dt == 0
			console.warn "BUG got dt of zero"
			return
		@beforePhysics.dispatch dt, @time
		@onPhysics.dispatch dt, @time
		@afterPhysics.dispatch dt, @time

		@beforeRender.dispatch dt, @time
		@onRender.dispatch dt, @time
		@afterRender.dispatch dt, @time

		@time += dt
		@onTickHandled.dispatch dt, @time


	bindPhys: (physical, visual) ->
		@afterPhysics.add ->
			visual.position.copy physical.position
			visual.quaternion.copy physical.quaternion

generateRock = (seed=Math.random()) ->
	perlin.seed seed
	radius = 1
	scale = radius
	noiseScale = 100
	geo = new THREE.IcosahedronGeometry radius, 1
	dir = new THREE.Vector3
	for vert in geo.vertices
		dir.copy vert
		dir.normalize()
		rnd = perlin.simplex3(vert.x*noiseScale, vert.y*noiseScale, vert.z*noiseScale)*scale
		dir.multiplyScalar Math.abs(rnd)*scale
		vert.add dir
	geo.verticesNeedUpdate = true
	geo.computeVertexNormals()
	geo.computeFaceNormals()
	rock = new THREE.Mesh geo, new THREE.MeshLambertMaterial do
		color: 0x64675F
	rock.castShadow = true
	rock.receiveShadow = true
	return rock

export addGround = (scene) ->
	groundTex = THREE.ImageUtils.loadTexture 'res/world/sandtexture.jpg'
	terrainSize = 1000
	textureSize = 5
	textureRep = terrainSize/textureSize
	groundNorm = THREE.ImageUtils.loadTexture 'res/world/sandtexture.norm.jpg'
	groundTex.wrapS = groundTex.wrapT = THREE.RepeatWrapping
	groundNorm.wrapS = groundNorm.wrapT = THREE.RepeatWrapping
	groundTex.repeat.set textureRep, textureRep
	groundNorm.repeat.set textureRep, textureRep
	groundTex.anisotropy = 12 #renderer.getMaxAnisotropy()
	groundMaterial = new THREE.MeshPhongMaterial do
		color: 0xffffff
		map: groundTex
		normalMap: groundNorm
		shininess: 20
	terrain = new THREE.Object3D
	terrain.receiveShadow = true
	groundGeometry = new THREE.PlaneGeometry terrainSize, terrainSize, 0, 0
	ground = new THREE.Mesh groundGeometry, groundMaterial
	ground.castShadow = false
	ground.receiveShadow = true
	ground.rotation.x = -Math.PI/2.0
	# To avoid z-fighting. Should be handled by
	# polygon offset, but it gives very weird results
	ground.position.y = -0.1
	groundBody = new Cannon.Body mass: 0
		..addShape new Cannon.Plane
		..quaternion.setFromAxisAngle new Cannon.Vec3(1,0,0), -Math.PI/2.0
	terrain.add ground
	scene.physics.add groundBody

	roadWidth = 7
	roadGeo = new THREE.PlaneGeometry terrainSize, roadWidth, 0, 0
	roadTex = THREE.ImageUtils.loadTexture 'res/world/road_texture.jpg'
	roadNorm = THREE.ImageUtils.loadTexture 'res/world/road_texture.norm.jpg'
	roadTex.anisotropy = 16#renderer.getMaxAnisotropy()
	roadTex.minFilter = THREE.LinearMipMapLinearFilter
	#roadTex.minFilter = THREE.LinearFilter
	roadTex.wrapS = roadTex.wrapT = THREE.RepeatWrapping
	roadNorm.wrapS = roadNorm.wrapT = THREE.RepeatWrapping
	roadTex.repeat.set textureRep/2.0, 1
	roadNorm.repeat.set textureRep/2.0, 1
	roadMat = new THREE.MeshPhongMaterial do
		map: roadTex
		shininess: 20
		normalMap: roadNorm
	road = new THREE.Mesh roadGeo, roadMat
	road.rotation.x = -Math.PI/2.0
	road.rotation.z = -Math.PI/2.0
	road.position.y = 0
	terrain.add road

	rocks = new THREE.Object3D()
	nRockTypes = 10
	rockPool = for i from 0 til nRockTypes
		generateRock()
	randomRock = ->
		rock = rockPool[Math.floor(Math.random()*rockPool.length)]
		return new THREE.Mesh rock.geometry, rock.material
	nRocks = Math.round(terrainSize*(2*200)/500)
	sizeDist = jStat.uniform(0.1, 0.6)
	zDist = jStat.uniform(-terrainSize/2, terrainSize/2)
	xDist = jStat.uniform(-200, 200)
	for i from 0 til nRocks
		x = xDist.sample()
		size = sizeDist.sample()
		if Math.abs(x) - Math.abs(size) < roadWidth
			continue
		z = zDist.sample()
		rock = randomRock()
		rock.position.x = x
		rock.position.z = z
		rock.scale.multiplyScalar size
		rock.scale.y *= 0.8
		rock.updateMatrix()
		rock.matrixAutoUpdate = false
		rocks.add rock

	terrain.add mergeObject rocks

	scene.visual.add terrain
	ahead = terrain.clone()
	behind = terrain.clone()
	scene.visual.add ahead
	scene.visual.add behind

	position = new THREE.Vector3
	scene.beforeRender.add ->
		position.setFromMatrixPosition scene.camera.matrixWorld
		nTerrains = Math.floor (position.z+terrainSize/2.0)/terrainSize
		terrain.position.z = nTerrains*terrainSize
		ahead.position.z = terrain.position.z + terrainSize
		behind.position.z = terrain.position.z - terrainSize


generateSnakePath = (rX, rY, s, terrainSize) ->
	c = 0.5522847498307933984022516322796
	ox = rX * c
	oy = rY * c
	dy = -2*rY
	if s == 0
		s = 0.00000000000000001
	k = (terrainSize/2 - rX - 1.75) - 500
	circle = new THREE.CurvePath()
	straight = new THREE.LineCurve3(new THREE.Vector3(-s, rX + k, 0), new THREE.Vector3(0, rX + k, 0))
	circle.add(straight)
	for i from 0 til 6
		curve1 = new THREE.CubicBezierCurve3(new THREE.Vector3(0, rX + k, 0), new THREE.Vector3(c*rY,rX + k, 0), new THREE.Vector3(rY, c*rX + k, 0), new THREE.Vector3(rY, 0 + k, 0))
		curve2 = new THREE.CubicBezierCurve3(new THREE.Vector3(rY, 0 + k, 0), new THREE.Vector3(rY, -c*rX + k, 0), new THREE.Vector3(c*rY, -rX + k, 0), new THREE.Vector3(0, -rX + k, 0))
		straight1 = new THREE.LineCurve3(new THREE.Vector3(0, -rX + k, 0), new THREE.Vector3(-s, -rX + k, 0))
		curve3 = new THREE.CubicBezierCurve3(new THREE.Vector3(-s, rX + dy + k, 0), new THREE.Vector3(-c*rY - s, rX + dy + k, 0),  new THREE.Vector3(-rY - s, c*rX + dy + k, 0), new THREE.Vector3(-rY - s, 0 + dy + k, 0))
		curve4 = new THREE.CubicBezierCurve3(new THREE.Vector3(-rY - s, 0 + dy + k, 0), new THREE.Vector3(-rY - s, -c*rX + dy + k, 0),  new THREE.Vector3(-c*rY - s, -rX + dy + k, 0), new THREE.Vector3(-s, -rX + dy + k, 0))
		straight2 = new THREE.LineCurve3(new THREE.Vector3(-s, rX + 2*dy + k, 0), new THREE.Vector3(0, rX + 2*dy + k, 0))
		circle.add(curve1)
		circle.add(curve2)
		circle.add(straight1)
		circle.add(curve3)
		circle.add(curve4)
		circle.add(straight2)
		k += 2*dy
	curve1 = new THREE.CubicBezierCurve3(new THREE.Vector3(0, rX + k, 0), new THREE.Vector3(c*rY,rX + k, 0), new THREE.Vector3(rY, c*rX + k, 0), new THREE.Vector3(rY, 0 + k, 0))
	curve2 = new THREE.CubicBezierCurve3(new THREE.Vector3(rY, 0 + k, 0), new THREE.Vector3(rY, -c*rX + k, 0), new THREE.Vector3(c*rY, -rX + k, 0), new THREE.Vector3(0, -rX + k, 0))
	straight1 = new THREE.LineCurve3(new THREE.Vector3(0, -rX + k, 0), new THREE.Vector3(-s, -rX + k, 0))
	circle.add(curve1)
	circle.add(curve2)
	circle.add(straight1)

	return circle


export addCurveGround = (scene, rx, ry, length) ->
	groundTex = THREE.ImageUtils.loadTexture 'res/world/ground_sand.jpg	'
	terrainSize = 4500
	textureSize = 5
	textureRep = terrainSize/textureSize
	groundNorm = THREE.ImageUtils.loadTexture 'res/world/sandtexture.norm.jpg'
	groundTex.wrapS = groundTex.wrapT = THREE.RepeatWrapping
	groundNorm.wrapS = groundNorm.wrapT = THREE.RepeatWrapping
	groundTex.repeat.set textureRep, textureRep
	groundNorm.repeat.set textureRep, textureRep
	groundTex.anisotropy = 12 #renderer.getMaxAnisotropy()
	groundMaterial = new THREE.MeshPhongMaterial do
		color: 0xffffff
		map: groundTex
		normalMap: groundNorm
		shininess: 20
	terrain = new THREE.Object3D
	terrain.receiveShadow = true
	groundGeometry = new THREE.PlaneGeometry terrainSize, terrainSize, 0, 0
	ground = new THREE.Mesh groundGeometry, groundMaterial
	ground.castShadow = false
	ground.receiveShadow = true
	ground.rotation.x = -Math.PI/2.0
	# To avoid z-fighting. Should be handled by
	# polygon offset, but it gives very weird results
	ground.position.y = -0.1
	groundBody = new Cannon.Body mass: 0
		..addShape new Cannon.Plane
		..quaternion.setFromAxisAngle new Cannon.Vec3(1,0,0), -Math.PI/2.0
	terrain.add ground
	scene.physics.add groundBody

	roadWidth = 3.5
	roadLenght = 20
	shape = new THREE.Shape()
	shape.moveTo(0, -0.5*roadWidth)
	shape.lineTo(0, 0.5*roadWidth)
	shape.lineTo(roadLenght, 0.5*roadWidth)
	shape.lineTo(roadLenght, -0.5*roadWidth)
	shape.lineTo(0, -0.5*roadWidth)

	circle = generateSnakePath(rx, ry, length, terrainSize)
	scene.centerLine = generateSnakePath(rx, ry, length, terrainSize)
	scene.centerLine.width = roadWidth
	extrudeSettings = {curveSegments: 2500, steps: 2500, bevelEnabled: false, extrudePath: circle}
	roadGeo = new THREE.ExtrudeGeometry shape, extrudeSettings
	roadTex = THREE.ImageUtils.loadTexture 'res/world/road_broken.jpg'
	roadNorm = THREE.ImageUtils.loadTexture 'res/world/road_texture.norm.jpg'
	roadTex.anisotropy = 12#renderer.getMaxAnisotropy()
	#roadTex.minFilter = THREE.LinearMipMapLinearFilter
	roadTex.minFilter = THREE.LinearFilter
	roadTex.wrapS = roadTex.wrapT = THREE.RepeatWrapping
	roadNorm.wrapS = roadNorm.wrapT = THREE.RepeatWrapping
	#roadTex.repeat.set textureRep/2.0, 1
	#roadNorm.repeat.set textureRep/2.0, 1
	roadMat = new THREE.MeshPhongMaterial do
		map: roadTex
		shininess: 20
		normalMap: roadNorm
	faces = roadGeo.faces
	roadGeo.faceVertexUvs[0] = []
	r = 0
	a = rx + 0.5 * roadWidth
	b = ry + 0.5 * roadWidth
	h = ((a - b) ^ 2) / ((a + b) 	^ 2)
	circum = Math.round(Math.PI*(a + b)*(1+(3*h/(10+(4-3*h) ^ 0.5))) + 2*length)
	x = circum / (roadGeo.faces.length)
	for i in [0 til roadGeo.faces.length/2 ]
		t = [new THREE.Vector2(r, 0), new THREE.Vector2(r, 1), new THREE.Vector2(r + x, 1), new THREE.Vector2(r + x, 0)]
		roadGeo.faceVertexUvs[0].push([t[0], t[1], t[3]])
		roadGeo.faceVertexUvs[0].push([t[1], t[2], t[3]])
		r += x
	roadGeo.uvsNeedUpdate = true
	road = new THREE.Mesh roadGeo, roadMat
	road.rotation.x = -Math.PI/2.0
	road.rotation.z = -Math.PI/2.0
	road.position.y = -0.09
	terrain.add road

	rocks = new THREE.Object3D()
	nRockTypes = 10
	rockPool = for i from 0 til nRockTypes
		generateRock()
	randomRock = ->
		rock = rockPool[Math.floor(Math.random()*rockPool.length)]
		return new THREE.Mesh rock.geometry, rock.material
	nRocks = Math.round(terrainSize*(2*200)/500)
	sizeDist = jStat.uniform(0.1, 0.6)
	zDist = jStat.uniform(-terrainSize/4, terrainSize/4)
	xDist = jStat.uniform(-terrainSize/2, terrainSize/2)
	rX = rx - 1
	rY = ry - 1
	for i from 0 til nRocks
		x = xDist.sample()
		size = sizeDist.sample()
		z = zDist.sample()
		cnt = false
		rW = roadWidth + 2
		xi = x - ((terrainSize/2 - rX - 1.75) - 500)
		if z <= 0 && z >= -length && xi < rx + rW && xi > rx - rW
				cnt = true
		for i from 0 til 6
			xi = x + i*rx*4 -((terrainSize/2 - rX - 1.75) - 500)
			if (((xi ^ 2 / ((rx + rW) ^ 2)  + (z ^ 2 / ((rY + rW) ^ 2))) <= 1)  && ((xi ^ 2 / ((rx - rW) ^ 2)  + (z ^ 2 / ((rY - rW) ^ 2))) > 1) && z >= 0)
				cnt = true
			if ((((xi - 2*rx) ^ 2 / ((rx + rW) ^ 2)  + ((z+length) ^ 2 / ((rY + rW) ^ 2))) <= 1)  && (((xi - 2*rx) ^ 2 / ((rx - rW) ^ 2)  + ((z+length) ^ 2 / ((rY - rW) ^ 2))) > 1) && z <= -length)
				cnt = true
			if z <= 0 && z >= -length && xi < -(rx*3 - rW) && xi > -(rx*3) - rW
				cnt = true
			if z <= 0 && z >= -length && xi < -(rx - rW) && xi > -rx - rW
				cnt = true
		if cnt == true
			continue
		rock = randomRock()
		rock.position.x = x
		rock.position.z = z
		rock.scale.multiplyScalar size
		rock.scale.y *= 0.8
		rock.updateMatrix()
		rock.matrixAutoUpdate = false
		rocks.add rock

	terrain.add mergeObject rocks

	scene.visual.add terrain

	position = new THREE.Vector3
	scene.beforeRender.add ->
		position.setFromMatrixPosition scene.camera.matrixWorld
		nTerrains = Math.floor (position.z+terrainSize/2.0)/terrainSize
		terrain.position.z = nTerrains*terrainSize


createPoleEnd = (x,z) ->
		size = 1
		geoEnd = new THREE.CylinderGeometry 0.032, 0.032, 0.25, 100
		geoEnd.verticesNeedUpdate = true
		geoEnd.computeVertexNormals()
		geoEnd.computeFaceNormals()
		poleEnd = new THREE.Mesh geoEnd, new THREE.MeshLambertMaterial do
			color: 0xFF0000
		poleEnd.castShadow = false
		poleEnd.receiveShadow = false

		poleEnd.position.x = x
		poleEnd.position.z = z
		poleEnd.position.y = -0.15
		poleEnd.scale.multiplyScalar size
		poleEnd.updateMatrix()
		poleEnd.matrixAutoUpdate = false

		return poleEnd

createPole = (x,z) ->
		size = 1
		geo = new THREE.CylinderGeometry 0.029, 0.029, 0.45, 20
		geo.verticesNeedUpdate = true
		geo.computeVertexNormals()
		geo.computeFaceNormals()
		pole = new THREE.Mesh geo, new THREE.MeshLambertMaterial do
			color: 0x000000
		pole.castShadow = true
		pole.receiveShadow = true

		pole.position.x = x
		pole.position.z = z
		pole.scale.multiplyScalar size
		pole.updateMatrix()
		pole.matrixAutoUpdate = false

		return pole

createBlock = (x,z) ->
		size = 1
		geo = new THREE.CylinderGeometry 0.35, 0.35, 0.35, 10


		poleTex = THREE.ImageUtils.loadTexture 'res/world/tyre.jpg'

		pole = new THREE.Mesh geo, new THREE.MeshPhongMaterial do
			map: poleTex
			shininess: 15
		pole.castShadow = true
		pole.receiveShadow = true

		pole.position.x = x
		pole.position.z = z

		pole.rotation.y = Math.PI*2.0*Math.random()
		return pole


#horrible copy-pasting

export addCircleGround = (scene, rx, ry, length, rocksOnPath, roadShape, texture) ->
	groundTex = THREE.ImageUtils.loadTexture 'res/world/ground_moon.png'
	roadTextureNorm = 'res/world/road_double.png'
	roadTextureAlt = 'res/world/road2_alpha8.png'
	
	terrainSize = 2000
	textureSize = 40

	textureRep = terrainSize/textureSize
	groundNorm = THREE.ImageUtils.loadTexture 'res/world/ground_moon_norm.png'
	groundTex.wrapS = groundTex.wrapT = THREE.RepeatWrapping
	groundNorm.wrapS = groundNorm.wrapT = THREE.RepeatWrapping
	groundTex.repeat.set textureRep, textureRep
	groundNorm.repeat.set textureRep, textureRep
	groundTex.anisotropy = 16 #renderer.getMaxAnisotropy()
	groundMaterial = new THREE.MeshPhongMaterial do
		color: 0xffffff
		map: groundTex
		normalMap: groundNorm
		shininess: 20
	terrain = new THREE.Object3D
	terrain.receiveShadow = true
	groundGeometry = new THREE.PlaneGeometry terrainSize, terrainSize, 0, 0
	ground = new THREE.Mesh groundGeometry, groundMaterial
	ground.castShadow = false
	ground.receiveShadow = true
	ground.rotation.x = -Math.PI/2.0
	# To avoid z-fighting. Should be handled by
	# polygon offset, but it gives very weird results
	ground.position.y = -0.1
	groundBody = new Cannon.Body mass: 0
		..addShape new Cannon.Plane
		..quaternion.setFromAxisAngle new Cannon.Vec3(1,0,0), -Math.PI/2.0
	terrain.add ground
	scene.physics.add groundBody

	generateCircle = (rX, rY, s) ->
		c = 0.5522847498307933984022516322796
		ox = rX * c
		oy = rY * c
		curve1 = new THREE.CubicBezierCurve3(new THREE.Vector3(0, rX, 0), new THREE.Vector3(c*rY,rX, 0), new THREE.Vector3(rY, c*rX, 0), new THREE.Vector3(rY, 0, 0))
		curve2 = new THREE.CubicBezierCurve3(new THREE.Vector3(rY, 0, 0), new THREE.Vector3(rY, -c*rX, 0), new THREE.Vector3(c*rY, -rX, 0), new THREE.Vector3(0, -rX, 0))
		straight1 = new THREE.LineCurve3(new THREE.Vector3(0, -rX, 0), new THREE.Vector3(-s, -rX, 0))
		curve3 = new THREE.CubicBezierCurve3(new THREE.Vector3(-s, -rX, 0), new THREE.Vector3(-c*rY - s, -rX, 0), new THREE.Vector3(-rY - s, -c*rX, 0), new THREE.Vector3(-rY - s, 0, 0))
		curve4 = new THREE.CubicBezierCurve3(new THREE.Vector3(-rY - s, 0, 0), new THREE.Vector3(-rY - s, c*rX, 0), new THREE.Vector3(-c*rY - s, rX, 0), new THREE.Vector3(-s, rX, 0))
		straight2 = new THREE.LineCurve3(new THREE.Vector3(-s, rX, 0), new THREE.Vector3(0, rX, 0))
		circle = new THREE.CurvePath()
		circle.add(curve1)
		circle.add(curve2)
		circle.add(straight1)
		circle.add(curve3)
		circle.add(curve4)
		circle.add(straight2)
		return circle

	generateStraight = ->
		straight = new THREE.LineCurve3(new THREE.Vector3(-2600, 0, 0), new THREE.Vector3(2600, 0, 0))
		path = new THREE.CurvePath()
		path.add(straight)
		return path

	generatePolesOnPath = (path, createPoles = false) ->
		poles = new THREE.Object3D()
		length = path.getLength()

		rx = 50
		yaw = 18.0
		s = (yaw/360*2*Math.PI*rx*3.6)
		nPoles = length/(s*0.9/3.6)

		rX = rx - 1
		rY = ry - 1
		#for i from 0 til nPoles
		#	point0 = path.getPointAt(i/nPoles)
		#	point1 =  path.getPointAt(i/nPoles + 0.1/length)
		#	x0 = (point0.y + point1.y) / 2 
		#	z0 = (point0.x + point1.x) / 2 
		#	dx = (point1.y - point0.y) 	
		#	dy = (point1.x - point0.x)
		#	dist = 3.67
		#
		#	x = x0 - dy*dist*10
		#	z = z0 + dx*dist*10	
		#	pole = createBlock(x,z)
		#	poles.add pole
		#
		#	x = x0 + dy*dist*10
		#	z = z0 - dx*dist*10	
		#	pole = createBlock(x,z)
		#	poles.add pole
		nPoles = length/(s/3.6)		
		if createPoles == true
			for i from 0 til nPoles
				x = path.getPointAt(i/nPoles).y
				z = path.getPointAt(i/nPoles).x
				pole = createPole(x,z)
				poles.add pole
				poleEnd = createPoleEnd(x,z)
				poles.add poleEnd
		return poles

	generatePollsStill = (path) ->
		poles = new THREE.Object3D()
		length = path.getLength()

		rx = 50
		s = (rx * 2 * Math.PI * 15 / 360.0)

		nPoles = length/(s)*2

		rX = rx - 1
		rY = ry - 1
		for i from 1 til 3
			x = path.getPointAt(i/nPoles).y
			z = path.getPointAt(i/nPoles).x
			pole = createPole(x,z)
			poleEnd = createPoleEnd(x,z)
			poles.add pole
			poles.add poleEnd

		for i from 1 til 3
			x = path.getPointAt(0.5 - (i/nPoles)).y
			z = path.getPointAt(0.5 - (i/nPoles)).x

			pole = createPole(x,z)
			poleEnd = createPoleEnd(x,z)
			poles.add pole
			poles.add poleEnd
		return poles

	generateRocks = (terrainSize) ->
		rocks = new THREE.Object3D()
		nRockTypes = 10
		rockPool = for i from 0 til nRockTypes
			generateRock()
		randomRock = ->
			rock = rockPool[Math.floor(Math.random()*rockPool.length)]
			return new THREE.Mesh rock.geometry, rock.material
		nRocks = Math.round(terrainSize*(200)/500)
		sizeDist = jStat.uniform(0.05, 0.15)
		rock_distance = 240
		zDist = jStat.uniform(-rock_distance, rock_distance)
		xDist = jStat.uniform(-rock_distance, rock_distance)
		rX = rx - 1
		rY = ry - 1
		for i from 0 til nRocks
			x = xDist.sample()
			size = sizeDist.sample()
			z = zDist.sample()
			cnt = false
			rW = 3.5 + 1.5
			if (((x ^ 2 / ((rX + rW) ^ 2)  + (z ^ 2 / ((rY + rW) ^ 2))) <= 1)  && ((x ^ 2 / ((rX - 2) ^ 2)  + (z ^ 2 / ((rY - 2) ^ 2))) > 1) && z >= 0)
				cnt = true
			if (((x ^ 2 / ((rX + rW) ^ 2)  + ((z+length) ^ 2 / ((rY + rW) ^ 2))) <= 1)  && ((x ^ 2 / ((rX - 2) ^ 2)  + ((z+length) ^ 2 / ((rY - 2) ^ 2))) > 1) && z <= -length)
				cnt = true
			if z <= 0 && z >= -length && x > (rX - 2) && x < rX + rW
				cnt = true
			if z <= 0 && z >= -length && x < -(rX - 2) && x > -rX - rW
				cnt = true
			if cnt == true
				continue
			rock = randomRock()
			rock.position.x = x
			rock.position.z = z
			rock.scale.multiplyScalar size
			rock.scale.y *= 0.8
			rock.updateMatrix()
			rock.matrixAutoUpdate = false
			rocks.add rock
		return rocks
	
	roadWidth = 3.5/1.5*3.5
	roadLenght = 4*roadWidth
	shape = new THREE.Shape()
	shape.moveTo(0, -0.5*roadWidth)
	shape.lineTo(0, 0.5*roadWidth)
	shape.lineTo(roadLenght, 0.5*roadWidth)
	shape.lineTo(roadLenght, -0.5*roadWidth)
	shape.lineTo(0, -0.5*roadWidth)

	circle = generateSnakePath(rx, ry, length, terrainSize)
	scene.centerLine = generateSnakePath(rx, ry, length, terrainSize)

	if roadShape == 1
		circle = generateStraight(rx, ry, length)
		scene.centerLine = generateStraight(rx, ry, length)
	if roadShape == 2
		circle = generateCircle(rx, ry, length)
		scene.centerLine = generateCircle(rx, ry, length)
	scene.centerLine.width = roadWidth
	extrudeSettings = {curveSegments: 2500, steps: 2500, bevelEnabled: false, extrudePath: circle}
	roadGeo = new THREE.ExtrudeGeometry shape, extrudeSettings

	if texture == undefined || texture == 0
		roadTex = THREE.ImageUtils.loadTexture roadTextureNorm
	else 
		roadTex = THREE.ImageUtils.loadTexture roadTextureAlt

	roadNorm = THREE.ImageUtils.loadTexture 'res/world/road_double_norm.png'
	roadTex.anisotropy = 16#renderer.getMaxAnisotropy()
	roadTex.minFilter = THREE.LinearMipMapLinearFilter
	#roadTex.minFilter = THREE.LinearFilter
	#roadTex.magFilter = THREE.LinearFilter
	roadTex.wrapS = roadTex.wrapT = THREE.RepeatWrapping
	roadNorm.wrapS = roadNorm.wrapT = THREE.RepeatWrapping
	#roadTex.repeat.set textureRep/2.0, 1
	#roadNorm.repeat.set textureRep/2.0, 1
	roadMat = new THREE.MeshPhongMaterial do
		map: roadTex
		shininess: 15
		normalMap: roadNorm
		transparent: true
	faces = roadGeo.faces
	roadGeo.faceVertexUvs[0] = []
	r = 0

	circum = Math.round(circle.getLength() / (roadLenght))
	x = circum * 4 / (roadGeo.faces.length / 2)
	for i in [0 til roadGeo.faces.length/2 ]
		t = [new THREE.Vector2(r, 0), new THREE.Vector2(r, 1), new THREE.Vector2(r + x, 1), new THREE.Vector2(r + x, 0)]
		roadGeo.faceVertexUvs[0].push([t[0], t[1], t[3]])
		roadGeo.faceVertexUvs[0].push([t[1], t[2], t[3]])
		r += x
	roadGeo.uvsNeedUpdate = true
	road = new THREE.Mesh roadGeo, roadMat
	road.rotation.x = -Math.PI/2.0
	road.rotation.z = -Math.PI/2.0
	road.position.y = -0.08
	terrain.add road

	if rocksOnPath == 1
		rocks = generatePolesOnPath(scene.centerLine, true)
	else
		#rocks = generateRocks(terrainSize)
		rocks = generatePolesOnPath(scene.centerLine)

	terrain.add mergeObject rocks

	scene.visual.add terrain
	#ahead = terrain.clone()
	#scene.visual.add ahead

	position = new THREE.Vector3
	scene.beforeRender.add ->
		position.setFromMatrixPosition scene.camera.matrixWorld
		nTerrains = Math.floor (position.z+terrainSize/2.0)/terrainSize
		terrain.position.z = nTerrains*terrainSize
		#ahead.position.z = terrain.position.z + terrainSize
