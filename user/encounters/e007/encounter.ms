// Our very first ship encounter!

if not globals.hasIndex("Encounter") then
	if env.importPaths.indexOf("/usr/src") == null then
		env.importPaths.push "/usr/src"
	end if
	import "uiWidgets"
	import "encounterBase"
	import "randomNames"
	import "item"
	import "listUtil"
	import "stationModel"
	import "shipModel"
	import "shipDisplay"
end if

encounter = new encounterBase.CombatEncounter

encounter.consider = function(station, arriving)
	probability = 0.80		// 80% chance of this encounter
	if rnd > probability then return null
	return self.consideration(station, arriving)
end function

// If the host app decides to present this encounter, then it will call
// this present method, with the data returned from consider():
encounter.present = function(data)
	description = "You have encountered an enemy ship. " +
	  "Battle stations!"

	self.ship = shipModel.newShipOfDesign("freighter")
	self.renderer = new shipDisplay.Renderer
	self.renderer.x = 720
	self.renderer.renderShip self.ship
	
	self.showDialog data, description
	game.beginCombat self
end function

// The player is trying to flee.  Return true if successful,
// or false to cancel and keep them in combat.
encounter.handleFlee = function()
	self.renderer.stop
	self.renderer = null
	return true
end function

if locals == globals then
	enc = new encounter
	station = new stationModel.Station
	enc.present enc.consideration({"name":"Demo"}, true)
end if
