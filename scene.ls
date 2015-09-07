Cannon = require 'cannon'
{Signal} = require './signal.ls'
jStat = require 'jstat'
P = require 'bluebird'
Co = P.coroutine
seqr = require './seqr.ls'
{loadCollada, mergeObject} = require './utils.ls'

{perlin=noise} = require './vendor/perlin.js'

# Todo: ugly
window.THREE = THREE = require 'three'
require './three.js/examples/js/SkyShader.js'

# TODO: Find a good fidelity/performance
# compromise parameters
export class Scene
	({@minStepDuration=1/60}={}) ->
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

		@physics = new Cannon.World
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

		@visual = new THREE.Scene

		@camera = new THREE.PerspectiveCamera 65/(16/9), 1, 0.01, 450000

		@time = 0

		@onPhysics.add (dt) ~>
			nSteps = Math.ceil dt/@minStepDuration
			stepdur = dt/nSteps
			@physics.step stepdur, dt, nSteps

	tick: (dt) ->
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
		color: 0xd3ab6d
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
	roadTex.anisotropy = 12#renderer.getMaxAnisotropy()
	#roadTex.minFilter = THREE.LinearMipMapLinearFilter
	roadTex.minFilter = THREE.LinearFilter
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

export addCircleGround = (scene, radius) ->
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

	roadWidth = 10
	roadLenght = 20
	rectShape = new THREE.Shape()
	rectShape.moveTo(0, 0)
	rectShape.lineTo(0, roadWidth)
	rectShape.lineTo(roadLenght, roadWidth)
	rectShape.lineTo(roadLenght, 0 )
	rectShape.lineTo(0, 0)

	generateCircle = (r) ->
		c = 0.5522847498307933984022516322796
		curve1 = new THREE.CubicBezierCurve3(new THREE.Vector3(0, r, 0), new THREE.Vector3(c*r,r, 0), new THREE.Vector3(r, c*r, 0), new THREE.Vector3(r, 0, 0))
		curve2 = new THREE.CubicBezierCurve3(new THREE.Vector3(r, 0, 0), new THREE.Vector3(r, -c*r, 0), new THREE.Vector3(c*r, -r, 0), new THREE.Vector3(0, -r, 0))
		curve3 = new THREE.CubicBezierCurve3(new THREE.Vector3(0, -r, 0), new THREE.Vector3(-c*r, -r, 0), new THREE.Vector3(-r, -c*r, 0), new THREE.Vector3(-r, 0, 0))
		curve4 = new THREE.CubicBezierCurve3(new THREE.Vector3(-r, 0, 0), new THREE.Vector3(-r, c*r, 0), new THREE.Vector3(-c*r, r, 0), new THREE.Vector3(0, r, 0))
		finalCurve = new THREE.CurvePath()
		finalCurve.add(curve1)
		finalCurve.add(curve2)
		finalCurve.add(curve3)
		finalCurve.add(curve4)
		return finalCurve

	curve = generateCircle(radius)
	extrudeSettings = {curveSegments: 1000, steps: 1000, bevelEnabled: false, extrudePath: curve}
	roadGeo = new THREE.ExtrudeGeometry rectShape, extrudeSettings
	console.log(roadGeo)
	roadTex = THREE.ImageUtils.loadTexture 'res/world/road_texture.jpg'
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
	for i in [0 til roadGeo.faces.length/2 ]
		v1 = roadGeo.vertices[faces[i*2].a]
		v2 = roadGeo.vertices[faces[i*2+1].c]
		x = Math.abs(v2.x - v1.x) / 20
		x = 0.05
		t = [new THREE.Vector2(r, 0), new THREE.Vector2(r, 1), new THREE.Vector2(r + x, 1), new THREE.Vector2(r + x, 0)]
		roadGeo.faceVertexUvs[0].push([t[0], t[1], t[3]])
		roadGeo.faceVertexUvs[0].push([t[1], t[2], t[3]])
		r += x
	roadGeo.uvsNeedUpdate = true
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
		z = zDist.sample()
		outer = radius + 10
		if (x ^ 2  + z ^ 2) < (radius + 1.25*roadWidth) ^ 2 && (x ^ 2  + z ^ 2) > (radius) ^ 2
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

