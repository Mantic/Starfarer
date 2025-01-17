// This module defines a Font class which can read fonts in BMF format
// version 1.1 or 1.2.  Reference: https://bmf.php5.cz/index.php?page=format
//
// Example of basic usage:
//	 f = Font.load(fontFilePath)
//	 w = f.width("Hello world!")
//   f.print "Hello world!", 480 - w/2, 320

// CharData class, storing data about just one character in a particular font.
CharData = {}

// Helper function to load one character into the given
// charData map.  Return the next data position after
// the character has been read (i.e., position of next char).
CharData.load = function(data, pos)
	self.width = data.byte(pos)
	self.height = data.byte(pos+1)
	self.relX = data.sbyte(pos+2)
	self.relY = data.sbyte(pos+3)
	self.shift = data.sbyte(pos+4)
	self.colors = []
	pos = pos + 5
	bytes = self.width * self.height
	if bytes then
		for i in range(0, bytes-1)
			self.colors.push data.byte(pos+i)
		end for
	end if
	return pos + bytes
end function	

// Font class, storing all data about a particular font.
Font = {}
Font.data = null
Font.chars = null		// key: character; value: charData map
Font.kernMap = null		// key: char1; value: map from char2->kern
Font.imgCache = null	// key: character; value: Image
Font.altColors = null	// key: color; value: [palette, imgCache]
Font.curAltColor = null	// current color in altColors

Font.setKern = function(c1, c2, kern)
	if self.kernMap == null then self.kernMap = {}
	if not self.kernMap.hasIndex(c1) then self.kernMap[c1] = {}
	self.kernMap[c1][c2] = kern
end function
Font.kern = function(c1, c2)
	if self.kernMap == null then return 0
	if not self.kernMap.hasIndex(c1) then return 0
	km = self.kernMap[c1]
	if not km.hasIndex(c2) then return 0
	return km[c2]
end function

// Font.load: Main entry point for reading a font from disk.
// Call this on the Font class itself (i.e. not an instance).
// Pass in the path to the font file; get back a new Font object.
Font.load = function(path)
	data = file.loadRaw(path)
	if data == null then return null
	
	f = new  Font
	f.data = data
	f.chars = {}
	f.imgCache = {}
	f.altColors = {}
	data.littleEndian = true
	vers = data.byte(4)
	//print "Font version: " + floor(vers/16) + "." + vers % 16
	f.lineHeight = data.sbyte(5)
	f.sizeOver = data.sbyte(6)
	f.sizeUnder = data.sbyte(7)
	f.addSpace = data.sbyte(8)
	f.sizeInner = data.sbyte(9)
	f.alphaBits = 0
	f.numPalettes = 1
	if vers >= 1.2 then
		f.alphaBits = data.byte(12)
		f.numPalettes = data.byte(13) + 1
	end if
	palSize = data.byte(16)
	f.palette = []
	for i in range(0, palSize-1)
		f.palette.push color.rgb(data.byte(17+i*3)*4, data.byte(18+i*3)*4, data.byte(19+i*3)*4)
	end for
	titleLen = data.byte(17+palSize*3)
	f.title = data.utf8(18+palSize*3, titleLen)
	//print f.title
	pos = 18 + palSize*3 + titleLen
	
	// Read ASCII characters
	numAsciiChars = data.short(pos)
	pos = pos + 2
	//print numAsciiChars + " ASCII characters"
	
	for i in range(1, numAsciiChars)
		// Read one character
		charData = new CharData
		charData.charCode = data.byte(pos)
		pos = pos + 1
		pos = charData.load(data, pos)
		
		f.chars[char(charData.charCode)] = charData
	end for
	if pos >= data.len then return f
	
	// Read non-ASCII characters
	numOtherChars = data.uint(pos)
	pos = pos + 4
	//print numOtherChars + " non-ASCII characters"
	for i in range(1, numOtherChars)
		// Read one character
		charData = new CharData
		charData.charCode = data.uint(pos)
		pos = pos + 4
		pos = charData.load(data, pos)
		
		f.chars[char(charData.charCode)] = charData
	end for
	
	// Read kerning info
	if pos >= data.len then return f
	kernCount = data.ushort(pos)
	//print kernCount + " kerning pairs"
	pos = pos + 2
	for i in range(1, kernCount)
		c1 = data.uint(pos)
		c2 = data.uint(pos+4)
		k = data.short(pos+8)
		f.setKern char(c1), char(c2), k
		pos = pos + 10
	end for
	return f
end function

// Get the character data for the given character
// Return null if not found.  (But if we fail to find
// a lowercase letter, automatically look for upper case.)
Font.charData = function(c)	
	if self.chars.hasIndex(c) then return self.chars[c]
	c = c.upper
	if self.chars.hasIndex(c) then return self.chars[c]
	return null	
end function

// Render the given character into any drawing context 'g'
// which has setPixel method.  This includes both Image
// and PixelDisplay.  Note that for character 'c' you can
// either pass in a string (the character), or a CharData object.
// (Most users will use print or printChar, below.)
Font.renderChar = function(c, g, destX=0, destY=0)
	if c isa string then d = self.charData(c) else d = c
	if d == null then return null
	clrRange = 2^(8 - self.alphaBits)
	alphaScale = 255/(2^self.alphaBits - 1)
	baseColor = self.palette[0]
	if d.width and d.height then
		i = 0
		for bitmapY in range(d.height - 1)
			for bitmapX in range(0, d.width - 1)
				c = d.colors[i]
				i = i + 1
				if not c then continue
				if self.alphaBits then
					a = floor(c / clrRange) * alphaScale
					pixelColor = baseColor + hex2(a)
				else
					pixelColor = self.palette[c-1]
				end if
				g.setPixel destX + bitmapX, destY + bitmapY, pixelColor
			end for
		end for		
	end if
end function

// Make and return an Image of the given character.
Font.makeCharImage = function(c)
	d = self.charData(c)
	if d == null then return null
	img = Image.create(d.width, d.height, color.clear)
	self.renderChar d, img
	return img
end function

// Get an Image that represents the given character.
// This method uses a cache, so is faster after the first call.
Font.getCharImage = function(c)
	if not self.imgCache.hasIndex(c) then self.imgCache[c] = self.makeCharImage(c)
	return self.imageCache[c]
end function

// Change the color of this font for subsequent drawing.
Font.setColor = function(clr)
	if clr == self.curAltColor then return
	if self.altColors.hasIndex(clr) then
		// This is an alternate color we have seen before; just switch back
		// to the palette and image cache we used then.
		palAndCache = self.altColors[clr]
		self.palette = palAndCache[0]
		self.imgCache = palAndCache[1]
	else
		// This is a new alt color.  Set up a new palette and image cache.
		if clr isa string then
			self.palette = self.palette[:]
			self.palette[0] = clr
		else
			self.palette = clr
		end if
		self.imgCache = {}
		// And store it for future reuse.
		self.altColors[clr] = [self.palette, self.imgCache]
	end if
end function

// Render (draw) the given character to gfx, and return how
// far to shift the cursor.  This uses the image cache, so
// it gets faster after the first drawing of each character.
Font.printChar = function(c, x=480, y=320)
	d = self.charData(c)
	if d == null then return 0
	img = null
	if self.imgCache.hasIndex(c) then
		img = self.imgCache[c]
	else if d.width > 0 then
		img = self.makeCharImage(c)
		self.imgCache[c] = img
	end if
	x = x + d.relX
	if img != null then
		y = y - self.sizeOver - d.relY - img.height
		gfx.drawImage img, x, y
	end if
	return d.shift
end function

// Print the given string to gfx at the given location.
Font.print = function(s, x=20, y=320)
	lastc = ""
	kernCount = 0
	for c in s
		if self.kern(lastc, c) then
			//print lastc + c + ": " + self.kern(lastc, c)
			kernCount = kernCount + 1
		end if
		x = x + self.kern(lastc, c)
		x = x + self.printChar(c, x, y) + self.addSpace
		lastc = c
	end for
	//print "Kern applied to " + kernCount + "/" + (s.len-1) + " pairs"
end function

// Print the given string to gfx, centered horizontally on the given x.
Font.printCentered = function(s, x=480, y=320)
	self.print s, x - self.width(s)/2, y
end function

// Print the given string to gfx, right-aligned on x.
Font.printRight = function(s, x=940, y=320)
	self.print s, x - self.width(s), y
end function

// Return the width of the given string in this font.
Font.width = function(s)
	sum = 0
	lastc = ""
	for c in s
		d = self.charData(c)
		sum = sum + d.shift + self.addSpace + self.kern(lastc, c)
		lastc = c
	end for
	return sum
end function

// Return the number of characters of the given string that
// fit a given width.
Font.lenToFit = function(s, width=100)
	if not s or not (s isa string) then return 0
	if self.width(s) <= width then return s.len
	lo = 1
	hi = s.len
	while lo + 1 < hi
		mid = floor((lo + hi) / 2)
		if self.width(s[:mid]) <= width then
			lo = mid
		else
			hi = mid
		end if
	end while
	return lo
end function

// Demo program: find the fonts directory, then load and display
// every font found therein.
demo = function()
	clear; text.row = 0
	
	fontsFolder = "/usr/fonts"
	if not file.exists(fontsFolder) then fontsFolder = "fonts"
	if not file.exists(fontsFolder) then
		print "Unable to locate fonts folder."
		return
	end if
	
	y = 640
	for fontFile in file.children(fontsFolder)
		if fontFile[-4:] != ".bmf" then continue
		f = Font.load(file.child(fontsFolder, fontFile))
		if f == null then	continue
		f.print fontFile + ": " + f.title, 10, y + f.sizeOver
		y = y - f.lineHeight - 4
	end for
end function

if locals == globals then demo
