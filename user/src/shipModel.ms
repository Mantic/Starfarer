// This is the data model for a ship (either the player ship, or an
// NPC ship).  It contains everything we need to know about its layout,
// equipment, and current status.

import "constants"
import "qa"
import "listUtil"
if not globals.hasIndex("Door") then import "door"
if not globals.hasIndex("Item") then import "item"
if not globals.hasIndex("Character") then import "character"
if not globals.hasIndex("systems") then import "systems"

//----------------------------------------------------------------------
// Wall: an ordinary wall between cells.  Considered unbreachable.
//----------------------------------------------------------------------
Wall = {}
Wall.name = "wall"
Wall.isOpen = false		// walls should ALWAYS be closed
Wall.canOpen = false	// and cannot be opened, even by the crew

//----------------------------------------------------------------------
// Cell class: information about one map cell, including whether it is
// walkable, what equipment or cargo is there, whether it is on fire,
// its air quality, etc.
//----------------------------------------------------------------------
Cell = {}
Cell.contents = null		// an Item instance, or null
Cell.col = 0				// column within its ship map
Cell.row = 0				// row within its ship map
Cell.air = 100				// air quality, from 0 (vacuum) - 100 (fine)
Cell.fire = 0				// on fire? 0 (nope) to 100 (raging inferno)
Cell.walls = null			// list of wall or door in each direction (NORTH, etc.)
Cell.type = Celltype.STANDARD

Cell.make = function(col, row)
	noob = new Cell
	noob.col = col; noob.row = row
	noob.walls = [null, null, null, null]
	return noob
end function

Cell.placeItem = function(item)
	qa.assert self.contents == null
	self.contents = item
	item.col = self.col; item.row = self.row
end function

// Cell.walkable: returns whether an agent can step into this cell.
Cell.walkable = function()
	return self.contents == null or not self.contents.blocksWalking
end function

// Cell.canExitInDir: return whether a character could exit this cell
// in the given direction.  If assumeDoorsOpen is true, then assume
// any door that can be opened, will be opened.
Cell.canExitInDir = function(direction, assumeDoorsOpen=true)
	if self.walls[direction] == null then return true	// no door/wall
	wallInDirection = self.walls[direction]
	return wallInDirection.isOpen or (assumeDoorsOpen and wallInDirection.canOpen)
end function


//----------------------------------------------------------------------
// Ship: everything there is to know about a ship.
//----------------------------------------------------------------------

Ship = {}
Ship.maxHp = 20			// hull points (basically ship health)
Ship.hp = Ship.maxHp
Ship.jumpFuel = 5		// how many jumps we can make before refueling
Ship.directory = null   // where is the shipdata located
Ship.mapOffset = [0,0]  // x,y offset for map image
Ship.minions = []		// living things on a ship
Ship.incomingTypes = []	// list of ItemTypes bought but not yet loaded
Ship.outgoingTypes = []	// list of ItemTypes sold but not yet unloaded
Ship.systems = []		// list of System instances installed in the ship
Ship.reactor = null		// reactor system (always self.systems[0])

// Ship.init: initialize this ship with a blank map.  The map is initialized
// to all nulls, meaning not usable by any means (i.e. not part of the ship
// interior).  See the methods below to procedurally set up rooms etc.
Ship.init = function(columns, rows)
	// set up a map, as a 2D array of Cells (or null) indexed as [column][row]
	self.columns = columns
	self.rows = rows
	self.columnRange = range(0, columns-1)
	self.rowRange = range(0, rows-1)
	self.map = list.init2d(columns, rows)
	
	self.minions = []
	self.incomingTypes = []
	self.outgoingTypes = []
	
	// NOTE: we no longer set up some default systems.
	// Ship files will need to set them up themselves.
	// Always put the reactor first, followed by others.
	self.systems = []
end function

Ship.distributePower = function()
	// Calculate power output from the reactor, and distribute it to
	// all other systems, left to right, leaving any excess power
	// in the reactor itself.
	powerLeft = self.reactor.setPoint
	for system in self.systems
		if system == self.reactor then continue
		power = system.maxPossiblePower
		if power > powerLeft then power = powerLeft
		system.curPower = power
		powerLeft = powerLeft - power
	end for
	self.reactor.curPower = powerLeft
end function

// Ship.walkable: return whether an agent can step in the given
// position (given as a [column, row] list).  In other words: is the
// given position in bounds, and a walkable Cell?
Ship.walkable = function(colRow)
	if colRow[0] < 0 or colRow[0] >= self.columns then return false
	if colRow[1] < 0 or colRow[1] >= self.rows then return false
	c = self.map[colRow[0]][colRow[1]]
	return c != null and c.walkable
end function

// Ship.walkableNeighbors: return a list of [col,row] positions
// which can be entered from the given [col,row] point on the map.
// That means neighbors that are walkable, without a wall or
// closed door in between.
Ship.walkableNeighbors = function(colRow)
	result = []
	col = colRow[0]; row = colRow[1]
	c = self.map[col][row]
	for dir in DIRECTIONS
		if not c.canExitInDir(dir) then continue
		nextPos = [col + constants.dx(dir), row + constants.dy(dir)]
		if self.walkable(nextPos) then
			result.push nextPos
			if c.canExitInDir((dir+1)%4) then
				diag = [nextPos[0] - constants.dy(dir), nextPos[1] + constants.dx(dir)]
				if self.walkable(diag) then
					diagCell = self.map[diag[0]][diag[1]]
					if diagCell.canExitInDir((dir+2)%4) and diagCell.canExitInDir((dir+3)%4) then
						result.push diag
					end if 
				end if
			end if
		end if
			
	end for
	return result
end function

// Get a cell from our map, if it exists and is in bounds.
Ship.getCell = function(col, row)
	qa.assert col isa number and row isa number
	cell = null
	if col >= 0 and col < self.columns and row >= 0 and row < self.rows then cell = self.map[col][row]
	return cell
end function

// Boolean value that is true if cell at [col][row] is a cargo exchange cell and is empty
Ship.isFreeCargoCell = function(col, row)
	c = self.getCell(col, row)
	if c == null then return false
	return c.type == Celltype.CARGO_IN and c.contents == null
end function

// Boolean value that is true if cell at [col][row] is a cargo exchange cell and is not empty
Ship.isFullCargoCell = function(col, row)
	c = self.getCell(col, row)
	if c == null then return false
	return c.type == Celltype.CARGO_IN and c.contents != null
end function

Ship.isCargoOutCell = function(col, row)
	c = self.getCell(col, row)
	if c == null then return false
	return c.type == Celltype.CARGO_OUT
end function

// Returns a list of all currently free cargo cells on the ship
Ship.getFreeCargoInCells = function()
	result = []
	for col in self.columnRange
		for row in self.rowRange
			if self.isFreeCargoCell(col, row) then result.push self.getCell(col,row)
		end for
	end for
	return result
end function

// Returns a single currently free cargo cell on the ship, if any
Ship.getAnyFreeCargoInCell = function()
	for col in self.columnRange
		for row in self.rowRange
			if self.isFreeCargoCell(col, row) then return self.getCell(col,row)
		end for
	end for
	return null
end function

Ship.getAnyFreeCellPreferCargoInCell = function()
	result = self.getAnyFreeCargoInCell()
	if result == null then
		for col in self.columnRange
			for row in self.rowRange
				if self.getCell(col, row).contents == null then result = self.getCell(col,row)
			end for
		end for
	end if
	return result
end function

Ship.getFullCargoInCells = function()
	result = []
	for col in self.columnRange
		for row in self.rowRange
			if self.isFullCargoCell(col, row) then result.push self.getCell(col,row)
		end for
	end for
	return result
end function

Ship.getCargoOutCells = function()
	result = []
	for col in self.columnRange
		for row in self.rowRange
			if self.isCargoOutCell(col,row) then result.push self.getCell(col, row)
		end for
	end for
	return result
end function

Ship.addCargo = function(item)
	if item isa Item then
		freeCargoCells = self.getFreeCargoInCells
		if freeCargoCells.len > 0 then freeCargoCells[0].placeItem item
	end if
end function

Ship.removeCargo = function()
	removedItem = null
	fullCargoCells = self.getFullCargoInCells
	if fullCargoCells.len > 0 then
		removedItem = fullCargoCells[0].contents
		fullCargoCells[0].contents = null
	end if
	return removedItem
end function

Ship.findItemOfType = function(type)
	for col in self.columnRange
		for row in self.rowRange
			if self.map[col][row] == null then continue
			c = self.map[col][row].contents
			// Note: you might think we could use `c isa type` here.
			// But that doesn't always work reliably, if the calling code is
			// in some module that has imported item separately and so may
			// have a different instance of the type class.  Checking the
			// name always works.
			if c != null and c.name == type.name then return c
		end for
	end for
	return null
end function

Ship.systemAt = function(col, row)
	for system in self.systems
		if col >= system.col and col <= system.col + system.width - 1 and 
		   row >= system.row and row <= system.row + system.height - 1 then return system
	end for
	return null
end function


// Find the minion (if any) at a given row and column (position map).
Ship.minionAt = function(col,row)
	for minion in self.minions
		if minion.col == col and minion.row == row then return minion
	end for
	return null
end function

Ship.noteItemPickedUp = function(item)
	cell = self.getCell(item.col, item.row)
	if cell != null and cell.contents == item then cell.contents = null
	item.col = null; item.row = null
end function


Ship.update = function(dt)

end function

//----------------------------------------------------------------------
// Ship setup methods: these are used to prepare a ship map.
//----------------------------------------------------------------------

// Ship.digRoom: clear a room on the map.
Ship.digRoom = function(left, bottom, width, height)
	for col in range(left, left+width-1)
		for row in range(bottom, bottom+height-1)
			self.map[col][row] = Cell.make(col, row)
		end for
	end for
end function

Ship.place = function(col, row, direction, wallOrDoor)
	cell = self.getCell(col, row)
	if not cell isa Cell then
		print "Couldn't place " + wallOrDoor + " at " + col + "," + row
		return
	end if
	qa.assert cell isa Cell

	cell.walls[direction] = wallOrDoor
	nextCol = col + constants.dx(direction)
	nextRow = row + constants.dy(direction)

	// Door placement overrides walls
	override = false
	if wallOrDoor isa Door and self.getCell(nextCol, nextRow) != null then
		override = true
	end if

	if self.walkable([nextCol, nextRow]) or override then
		nextDir = constants.inverseDir(direction)
		self.map[nextCol][nextRow].walls[nextDir] = wallOrDoor
	end if
end function

Ship.removeWall = function(col, row, direction)
	cell = self.getCell(col, row)
	if not cell isa Cell then
		print "Couldn't remove wall/door at " + col + "," + row
		return
	end if
	qa.assert cell isa Cell

	cell.walls[direction] = null
	nextCol = col + constants.dx(direction)
	nextRow = row + constants.dy(direction)
	nextDir = constants.inverseDir(direction)

	// Remove shared wall in cell next door. 
	if self.getCell(nextCol, nextRow) != null then
		self.map[nextCol][nextRow].walls[nextDir] = null
	end if
end function

Ship.placeRoom = function(left, bottom, width, height)
	self.placeBottomWalls left, bottom, width
	self.placeTopWalls left, bottom + height - 1, width
	self.placeLeftWalls left, bottom, height
	self.placeRightWalls left + width - 1, bottom, height
end function

Ship.placeDoor = function(col, row, direction)
	self.place col, row, direction, Door.make
end function

Ship.placeBottomWalls = function(left, bottom, length)
	for col in range(left,left+length-1)
		self.place col, bottom, SOUTH, new Wall
	end for
end function

Ship.placeTopWalls = function(left, bottom, length)
	for col in range(left,left+length-1)
		self.place col, bottom, NORTH, new Wall
	end for
end function

Ship.placeLeftWalls = function(left, bottom, length)
	for row in range(bottom,bottom+length-1)
		self.place left, row, WEST, new Wall
	end for
end function

Ship.placeRightWalls = function(left, bottom, length)
	for row in range(bottom,bottom+length-1)
		self.place left, row, EAST, new Wall
	end for
end function

Ship.addSystem = function(system)
	system.repairLevel = system.maxPower
	system.curPower = system.maxPower
	system.setPoint = system.maxPower
	self.systems.push system
	if system isa systems.Reactor then self.reactor = system
end function

//----------------------------------------------------------------------
// Ship debug methods: these are used to display info about a ship,
// in text or graphical form.  Not meant for actual gameplay.
//----------------------------------------------------------------------

Ship.print = function()
	text.delimiter = " "
	print
	for row in range(self.rows-1, 0)
		for col in self.columnRange
			if self.map[col][row] == null then print "X" else print "."
		end for
		print char(13)
	end for
	text.delimiter = char(13)
	print
end function

Ship.printWalls = function(dir, wallChar = null)
	text.delimiter = " "
	print "Left"
	print char(13)
	for row in range(self.rows-1, 0)
		for col in self.columnRange
			cell = self.map[col][row]
			if cell == null then 
				print "X"
			else if cell.walls[dir] != null then
				if wallChar then print wallChar else print cell.walls[dir].name[0]
			else
				print "."
			end if
		end for
		print char(13)
	end for
	text.delimiter = char(13)
	print
end function

Ship.printWallsLeft = function()
	self.printWalls WEST, "|"
end function

Ship.printWallsRight = function()
	self.printWalls EAST, "|"
end function

Ship.printWallsAbove = function()
	self.printWalls NORTH, "-"
end function

Ship.printWallsBelow = function()
	self.printWalls SOUTH, "-"
end function

Ship.draw = function()
	gfx.clear
	
	drawWall = function(wallOrDoor, x1, y1, x2, y2, c)
		if wallOrDoor == null then return
		if wallOrDoor isa shipModel.Wall then
			gfx.line x1, y1, x2, y2, c
		else if wallOrDoor.isOpen then
			gfx.line x1, y1, x2, y2, color.aqua
		else
			gfx.line x1, y1, x2, y2, color.red
		end if
	end function

	offX = 20
	offY = 240

	// draw floor/contents	
	for col in self.columnRange
		x = (col * CELLSIZE) + offX
		for row in self.rowRange
			y = (row * CELLSIZE) + offY
			cell = self.map[col][row]
			if cell == null then
				gfx.line x+2, y+2, x+CELLSIZE-4, y+CELLSIZE-4, color.gray
				gfx.line x+2, y+CELLSIZE-4, x+CELLSIZE-4, y+2, color.gray
			else
				if cell.type == Celltype.CARGO_IN then 
					cellcolor = color.lime
				else if cell.type == Celltype.CARGO_OUT then
					cellcolor = color.orange
				else
					cellcolor = "#EEEEEE"
				end if
				gfx.fillRect x+1, y+1, CELLSIZE-2, CELLSIZE-2, cellcolor
				gfx.drawRect x, y, CELLSIZE, CELLSIZE, color.white
				if cell.contents != null then
					gfx.fillRect x+3, y+3, CELLSIZE-6, CELLSIZE-6, color.yellow
				end if
			end if
		end for
	end for
	
	// draw walls
	for col in self.columnRange
		x = (col * CELLSIZE) + offX
		for row in self.rowRange
			y = (row * CELLSIZE) + offY
			cell = self.map[col][row]
			if cell == null then continue
			drawWall cell.walls[SOUTH], x, y, x+CELLSIZE, y, color.green
			drawWall cell.walls[WEST], x, y, x, y+CELLSIZE, color.brown
			drawWall cell.walls[NORTH], x, y+CELLSIZE-1, x+CELLSIZE, y+CELLSIZE-1, color.navy
			drawWall cell.walls[EAST], x+CELLSIZE-1, y, x+CELLSIZE-1, y+CELLSIZE, color.purple
		end for
	end for
end function
	
//----------------------------------------------------------------------
// Module-level utility functions
//----------------------------------------------------------------------


newShipOfDesign = function(designName)
	dir = pwd
	cd "/usr/ships/" + designName
	import "shipData"
	cd dir
	return new shipData.ship
end function

demo = function(shipName="freighter")
	clear
	
	globals.ship = newShipOfDesign(shipName)
	ship.draw
	print "Free Cargo cells: " + ship.getFreeCargoInCells.len
	wait 1
	ship.addCargo new Item
	ship.draw
	print "Free Cargo cells: " + ship.getFreeCargoInCells.len
	wait 1
	ship.addCargo new Item
	ship.draw
	print "Free Cargo cells: " + ship.getFreeCargoInCells.len
	wait 1
	ship.addCargo new Item
	ship.draw
	print "Free Cargo cells: " + ship.getFreeCargoInCells.len
	wait 1
	ship.removeCargo
	ship.draw
	print "Free Cargo cells: " + ship.getFreeCargoInCells.len
	wait 1
	ship.removeCargo
	ship.draw
	print "Free Cargo cells: " + ship.getFreeCargoInCells.len
end function

runUnitTests = function()
	import "systems"
	
	setupTestCell = function()
		outer.testCell = shipModel.Cell.make(0,0)
	end function

	setupTestShip = function()
		outer.testShip = new shipModel.Ship
		testShip.init 10,10
	end function

	setupTestShipWithRoom = function()
		setupTestShip
		testShip.digRoom 0,0,2,2
	end function

	testCell = new Cell
	testCell.col = 1
	testCell.row = 1
	testCell.walls = [null, null, null, null]
	qa.assertEqual testCell, Cell.make(1,1)

	setupTestCell
	qa.assertEqual testCell.walkable, true
	qa.assertEqual testCell.contents, null
	testCell.placeItem new Item
	testItem = new Item
	testItem.col = 0; testItem.row = 0;
	qa.assertEqual testCell.contents, testItem
	qa.assertEqual testCell.walkable, false
	testCell.contents.blocksWalking = false
	qa.assertEqual testCell.walkable, true
	
	setupTestCell
	testCell.walls[globals.EAST] = new Wall
	qa.assertEqual testCell.walls, [{"__isa":{"name":"wall","isOpen":false,"canOpen":false}}, null, null, null]
	qa.assertEqual testCell.canExitInDir(globals.NORTH), true
	qa.assertEqual testCell.canExitInDir(globals.EAST), false
	testCell.walls[globals.NORTH] = Door.make
	qa.assertEqual testCell.canExitInDir(globals.NORTH), true
	qa.assertEqual testCell.canExitInDir(globals.NORTH, false), false

	setupTestShip
	testShip.digRoom 0,0,1,1
	qa.assertEqual testShip.map[0][0], Cell.make(0,0)
	qa.assertEqual testShip.map[0][1], null

	setupTestShipWithRoom
	qa.assertEqual testShip.map[0][0], Cell.make(0,0)
	qa.assertEqual testShip.map[0][1], Cell.make(0,1)
	qa.assertEqual testShip.map[1][0], Cell.make(1,0)
	qa.assertEqual testShip.map[1][1], Cell.make(1,1)

	qa.assertEqual testShip.walkable([0,0]), true
	qa.assertEqual testShip.walkable([-1,0]), false
	qa.assertEqual testShip.walkable([2,0]), false
	testShip.map[0][0].contents = new Item
	qa.assertEqual testShip.walkable([0,0]), false

	setupTestShipWithRoom
	qa.assertEqual testShip.getCell(0,0), Cell.make(0,0)
	qa.assertEqual testShip.getCell(2,2), null
	qa.assertEqual testShip.getCell(100,100), null //out of bounds Test

	setupTestShipWithRoom
	qa.assertEqual testShip.getCell(0,0).walls , [null, null, null, null]
	testShip.place(0,0,globals.EAST,new Wall)
	qa.assertEqual testShip.getCell(0,0).walls , [new Wall, null, null, null]
	qa.assertEqual testShip.getCell(1,0).walls , [null, null, new Wall, null]
	testShip.place(0,0,globals.NORTH, new Door)
	qa.assertEqual testShip.getCell(0,0).walls , [new Wall, new Door, null, null]

	setupTestShipWithRoom
	testShip.placeTopWalls(0,0,2)
	qa.assertEqual testShip.getCell(0,0).walls , [null, new Wall, null, null]
	qa.assertEqual testShip.getCell(1,0).walls , [null, new Wall, null, null]
	qa.assertEqual testShip.getCell(0,1).walls , [null, null, null, new Wall]
	qa.assertEqual testShip.getCell(1,1).walls , [null, null, null, new Wall]

	setupTestShipWithRoom
	testShip.placeTopWalls(0,1,2)
	qa.assertEqual testShip.getCell(0,0).walls , [null, null, null, null]
	qa.assertEqual testShip.getCell(1,0).walls , [null, null, null, null]
	qa.assertEqual testShip.getCell(0,1).walls , [null, new Wall, null, null]
	qa.assertEqual testShip.getCell(1,1).walls , [null, new Wall, null, null]

	setupTestShipWithRoom
	testShip.placeBottomWalls(0,0,2)
	qa.assertEqual testShip.getCell(0,0).walls , [null, null, null, new Wall]
	qa.assertEqual testShip.getCell(1,0).walls , [null, null, null, new Wall]
	qa.assertEqual testShip.getCell(0,1).walls , [null, null, null, null]
	qa.assertEqual testShip.getCell(1,1).walls , [null, null, null, null]

	setupTestShipWithRoom
	testShip.placeBottomWalls(0,1,2)
	qa.assertEqual testShip.getCell(0,0).walls , [null, new Wall, null, null]
	qa.assertEqual testShip.getCell(1,0).walls , [null, new Wall, null, null]
	qa.assertEqual testShip.getCell(0,1).walls , [null, null, null, new Wall]
	qa.assertEqual testShip.getCell(1,1).walls , [null, null, null, new Wall]

	setupTestShipWithRoom
	testShip.placeLeftWalls(0,0,2)
	qa.assertEqual testShip.getCell(0,0).walls , [null, null, new Wall, null]
	qa.assertEqual testShip.getCell(1,0).walls , [null, null, null, null]
	qa.assertEqual testShip.getCell(0,1).walls , [null, null, new Wall, null]
	qa.assertEqual testShip.getCell(1,1).walls , [null, null, null, null]

	setupTestShipWithRoom
	testShip.placeLeftWalls(1,0,2)
	qa.assertEqual testShip.getCell(0,0).walls , [new Wall, null, null, null]
	qa.assertEqual testShip.getCell(1,0).walls , [null, null, new Wall, null]
	qa.assertEqual testShip.getCell(0,1).walls , [new Wall, null, null, null]
	qa.assertEqual testShip.getCell(1,1).walls , [null, null, new Wall, null]

	setupTestShipWithRoom
	testShip.placeRightWalls(0,0,2)
	qa.assertEqual testShip.getCell(0,0).walls , [new Wall, null, null, null]
	qa.assertEqual testShip.getCell(1,0).walls , [null, null, new Wall, null]
	qa.assertEqual testShip.getCell(0,1).walls , [new Wall, null, null, null]
	qa.assertEqual testShip.getCell(1,1).walls , [null, null, new Wall, null]

	setupTestShipWithRoom
	testShip.placeRightWalls(1,0,2)
	qa.assertEqual testShip.getCell(0,0).walls , [null, null, null, null]
	qa.assertEqual testShip.getCell(1,0).walls , [new Wall, null, null, null]
	qa.assertEqual testShip.getCell(0,1).walls , [null, null, null, null]
	qa.assertEqual testShip.getCell(1,1).walls , [new Wall, null, null, null]

	setupTestShipWithRoom
	qa.assertEqual testShip.isFreeCargoCell(0,0) , false
	qa.assertEqual testShip.isFullCargoCell(0,0) , false
	testShip.getCell(0,0).type = Celltype.CARGO_IN
	qa.assertEqual testShip.isFreeCargoCell(0,0) , true
	qa.assertEqual testShip.isFullCargoCell(0,0) , false
	testShip.getCell(0,0).contents = new Item
	qa.assertEqual testShip.isFreeCargoCell(0,0) , false
	qa.assertEqual testShip.isFullCargoCell(0,0) , true

	setupTestShipWithRoom
	testShip.getCell(0,0).type = Celltype.CARGO_IN
	testShip.getCell(0,1).type = Celltype.CARGO_IN
	qa.assertEqual testShip.getFreeCargoInCells, [testShip.getCell(0,0),testShip.getCell(0,1)]
	qa.assertEqual testShip.getFullCargoInCells, []
	testShip.addCargo(new Item)
	qa.assertEqual testShip.getFreeCargoInCells, [testShip.getCell(0,1)]
	qa.assertEqual testShip.getFullCargoInCells, [testShip.getCell(0,0)]
	testShip.removeCargo
	qa.assertEqual testShip.getFreeCargoInCells, [testShip.getCell(0,0),testShip.getCell(0,1)]
	qa.assertEqual testShip.getFullCargoInCells, []

	setupTestShipWithRoom
	testCharacter = new character.Character
	testCharacter.boardShip(testShip)
	testCharacter.setMapPos [0,0]
	qa.assertEqual testShip.minions, [testCharacter]
	qa.assertEqual testShip.minionAt(0,0), testCharacter
	qa.assertEqual testShip.minionAt(1,1), null

	setupTestShipWithRoom
	testShip.getCell(0,0).type = Celltype.CARGO_OUT
	qa.assertEqual testShip.isCargoOutCell(0,0), true
	qa.assertEqual testShip.getCargoOutCells, [testShip.getCell(0,0)]

	setupTestShip
	sys = systems.System.make
	testShip.addSystem sys
	qa.assertEqual testShip.systems, [sys]

	print "shipModel unit tests complete."
end function

if locals == globals then
	shipModel = locals
	runUnitTests
end if
