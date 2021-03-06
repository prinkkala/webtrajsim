P = require 'bluebird'
Co = P.coroutine
$ = require 'jquery'
seqr = require './seqr.ls'

{addCircleGround, addCurveGround, Scene} = require './scene.ls'
{addVehicle} = require './vehicle.ls'
{NonSteeringControl} = require './controls.ls'
{DefaultEngineSound} = require './sounds.ls'
assets = require './assets.ls'

# Just a placeholder for localization
L = (s) -> s

ui = require './ui.ls'

export circleScene = seqr.bind (env, rx, ry, length, control = true, ellipse = true, rocksOnPath = false, straight = false) ->*
	{controls, audioContext, L} = env
	scene = new Scene

	if ellipse == true
		yield P.resolve addCurveGround scene, rx, ry, length
	else
		yield P.resolve addCircleGround scene, rx, ry, length, rocksOnPath, straight

	sky = yield P.resolve assets.addSky scene

	scene.playerControls = controls
	player = yield addVehicle scene, controls, objectName: 'player'
	player.eye.add scene.camera
	player.physical.position.x = scene.centerLine.getPointAt(0).y
	#for i from 0 til player.body.children.length - 1
	#	player.body.children[i].visible = false
	scene.player = player

	#lt = scene.visual.children.length - 1
	#scene.visual.children[lt - 1].visible = false
	#scene.visual.children[lt - 2].visible = false
	#scene.visual.children[lt - 3].visible = false
	#scene.visual.children[lt - 4].visible = false


	scene.soundPlay = false
	scene.soundTs = 0
	scene.prevTime = 0
	scene.player.prevSpeed = 0
	scene.dT = 0
	scene.outside = {out: false, totalTime: 0}
	scene.scoring = {score: 0, missed: 0, trueYes: 0, falseYes: 0, trueNo: 0, falseNo: 0, maxScore: 0}
	scene.player.roadPhase = {direction: "None", phase: "None"}
	scene.end = false
	scene.player.pos = 0
	scene.player.react = false
	scene.predict = []
	for i from 0 til 5
		scene.predict.push new THREE.Vector3(0,0,0)
	scene.targetPresent = false
	scene.targetScreen = false
	scene.transientScreen = false
	scene.reacted = true
	scene.controlChange = false
	scene.prev = [0,0,0,0,0]

	#scene.player.scoremeter = ui.gauge env,
	#	name: L "Speed"
	#	unit: L "km/h"
	#	value: ->
	#		score = scene.player.getSpeed()*3.6
	#		Math.round score
	#scene.player.scoremeter = ui.gauge env,
	#	name: L "Score"
	#	unit: L "times"
	#	value: ->
	#		score = scene.scoring.score
	#scene.player.scoremeter = ui.gauge env,
	#	name: L "True negative"
	#	unit: L "times"
	#	value: ->
	#		score = scene.scoring.trueNo
	#scene.player.scoremeter = ui.gauge env,
	#	name: L "False positive"
	#	unit: L "times"
	#	value: ->
	#		score = scene.scoring.falseYes
	#scene.player.scoremeter = ui.gauge env,
	#	name: L "True positive"
	#	unit: L "times"
	#	value: ->
	#		score = scene.scoring.trueYes
	#scene.player.missed = ui.gauge env,
	#	name: L "Missed"
	#	unit: L "times"
	#	value: ->
	#		score = scene.scoring.missed
	#scene.player.outside = ui.gauge env,
	#	name: L "Outside"
	#	unit: L "seconds"
	#	value: ->
	#		score = scene.outside.totalTime
	#		score.toFixed(2)
	engineSounds = yield DefaultEngineSound audioContext
	gainNode = audioContext.createGain()
	gainNode.connect audioContext.destination
	engineSounds.connect gainNode
	scene.afterPhysics.add ->
		rev = Math.abs(player.getSpeed())/(200/3.6)
		rev = Math.max 0.1, rev
		rev = (rev + 0.1)/1.1
		gain = scene.playerControls.throttle
		gain = (gain + 0.5)/1.5
		gainNode.gain.value = gain
		engineSounds.setPitch rev*2000
	if control
		scene.onStart.add engineSounds.start
		scene.onExit.add engineSounds.stop

	scene.preroll = ->
		# Tick a couple of frames for the physics to settle
		scene.tick 1/60
		n = 100
		t = Date.now()
		for [0 to n]
			scene.tick 1/60
		console.log "Prewarming FPS", (n/(Date.now() - t)*1000)
	return scene

