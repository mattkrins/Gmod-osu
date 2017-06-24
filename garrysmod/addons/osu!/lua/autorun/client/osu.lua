// Apologies to anyone reading this code in advance, I wrote this super-hacky proof-of-concept in a few hours with no desire to further develop it.
local OSU = {Song = {}}
local osuGUI = {}

OSU.dataPath = "osu/songs/"
OSU.songPath = false
OSU.musicPath = false
OSU.mapPath = false
OSU.startTime = false
OSU.file = false
OSU.sound = false
OSU.playing = false
OSU.MaxHealth = 1000
OSU.Health = 0
OSU.Combo = 0
OSU.Index = {Beat = 1,Timing = 1}
OSU.Stop = function( self, fade )
	print("Stopping...")
	if self.sound then
		if fade then
			timer.Create( "FadeOut", 0.1, 10, function()
				if !self.sound then return end
				self.sound:SetVolume( math.Clamp((self.sound:GetVolume() or 1 ) - 0.1,0,1) )
				if (self.sound:GetVolume() or 1) <= 0.1 then self.sound:Stop() self.sound = false end
			end )
		else
			self.sound:Stop() self.sound = false
		end
	end
	if timer.Exists( "SONG" ) then timer.Remove( "SONG" ) end
	self.playing = false
	self:Reset()
end
OSU.GetTiming = function( self ) return (self.Index.Timing or 1) end
OSU.GetBeat = function( self ) return (self.Index.Beat or 1) end
OSU.Beat = function( self )
	if !timer.Exists( "SONG" ) then return self:Stop() end
	if !self.Song.HitObjects or !self.Song.HitObjects[self:GetBeat()] or !self.sound then return self:Stop() end
	print("Beat "..self:GetBeat().." ( "..(CurTime()-self.startTime).." )")
	osuGUI:Beat()
	self.Index.Beat = self:GetBeat() + 1
end
OSU.GetTime = function( self ) return ( (CurTime() - (self.startTime or CurTime()))*1000 ) end
OSU.IsTime = function( self, time )
	local millisecond = self:GetTime()
	if (millisecond + (FrameTime()*1000) + 100) >= time then return true end
	return false
end
OSU.KeysDown = {}
OSU.Hit = function( self, key )
	if self.KeysDown[key] then return end
	self.KeysDown[key] = true
	local beat = osuGUI:MouseOver()
	if !beat then return end
	osuGUI:Hit(beat)
end
OSU.Think = function( self )
	if !self.playing then return end
	if !IsValid(osuGUI.Map) then return self:Stop() end	
	// Fail if we run out of health
	if self.Health <= 0 then
		osuGUI:Fail()
		return self:Stop(true)
	end
	// Trigger each beat when it's time.
	local offset = 1000
	local Beat = self.Song.HitObjects[self:GetBeat()] or {}
	if Beat[3] and self:IsTime(tonumber(Beat[3]-offset)) then self:Beat() end
	// Trigger each time point when it's time.
	local Point = self.Song.TimingPoints[self:GetTiming()] or {}
	if Point[1] and self:IsTime(tonumber(Point[1])) then
		self.Index.Timing = self:GetTiming() + 1
		if tonumber(Point[2]) <= 0 then return end
		self.BPM = tonumber(Point[2])/1000
	end
	
	// Check if we hit z, x, m1 or m2
	local keys = {KEY_Z, KEY_X, MOUSE_LEFT, MOUSE_RIGHT}
	for _,v in pairs( keys ) do
		if input.IsKeyDown( v ) or input.IsMouseDown( v ) then
			self:Hit(v)
		else
			self.KeysDown[v] = false
		end
	end
	
	// Drain health slowly
	self.Health = (self.Health - 1)
	osuGUI:Update()
	
end
OSU.Skip = function( self )
	if timer.Exists( "AudioLeadIn" ) then timer.Remove( "AudioLeadIn" ) end
	self:Play()
end
OSU.Play = function( self )
	print("Playing Song...")
	sound.PlayFile( "data/"..self.musicPath, "noblock noplay", function( this )
		if ( !IsValid( this ) ) then print("Audio Error!") return self:Stop() end
		self.sound = this
		this:SetVolume(1)
		self.startTime = CurTime()
		this:Play()
		osuGUI:Start()
		// Start song thinker
		timer.Create( "SONG", 0, 0, function() self:Think() end )
	end )
end
OSU.Reset = function( self )
	self.Index.Beat = 1
	self.startTime = false
	self.Health = self.MaxHealth
	self.Combo = 0
	self.Song = {}
end
OSU.Start = function( self )
	if !self:ValidMusic(self.musicPath) then return self:Stop() end
	print("Starting...")
	self.playing = true
	osuGUI:Load()
	timer.Create( "AudioLeadIn", (tonumber(self.Song.AudioLeadIn or 0.1) / 1000.0), 1, function() self:Play() end )
end
OSU.ValidMusic = function( self, musicPath ) if file.Exists( musicPath, "DATA" ) then return true end return false end
OSU.ValidMap = function( self, filePath )
	if !filePath or !file.Exists( self.dataPath..filePath, "DATA" ) then return false end
	for _,f in pairs(file.Find(self.dataPath..filePath .."/*", "DATA") or {}) do if string.GetExtensionFromFilename( f ) == "osu" then return f end end
	return false
end
OSU.Load = function( self, filePath )
	print("Loading Song: ",filePath)
	self:Reset()
	local Map = self:ValidMap(filePath) or false
	if !Map then return self:Stop() end
	self.songPath = self.dataPath..filePath	
	// Read and format map file
	local songData = file.Read( self.songPath.."/"..Map, "DATA" )
	if !songData then return self:Stop() end
	self.file = string.Explode( "\n", songData )
	local fileHeaders = {
		AudioLeadIn = 1,
		AudioLeadIn = 1,
		PreviewTime = 1,
		AudioFilename = 1,
		HitObjects = 2,
		TimingPoints = 2
	}
	for k,v in pairs( self.file ) do
		// Remove comments
		if ( string.find( v, "//" ) ) then self.file[k] = nil continue end
		for head, type in pairs( fileHeaders ) do
			if ( string.find( v, head ) ) then
				if type == 1 then
					self.Song[head] = string.Trim( string.Explode( ":", v )[2] )
				end
				if type == 2 then
					self.Song[head] = k+1
				end
			end
		end
	end
	// TODO: Implement sliders & spinners
	// Format CSV sub-tables
	local fileTables = {
		HitObjects = {},
		TimingPoints = {}
	}
	for head,tab in pairs( fileTables ) do
		for k,v in pairs( self.file ) do
			if k < self.Song[head] then continue end
			local obj = string.Explode( ",", v )
			if #obj >= 2 and !string.find( obj[1], " " ) then table.insert(tab, obj) else break end
		end
		self.Song[head] = table.Copy(tab)
	end
	// Error checking
	if #self.Song.HitObjects < 1 then return false end
	if !self.Song.AudioFilename then return false end
	self.musicPath = self.songPath.."/"..self.Song.AudioFilename
	self:Start()
end

local function drawCircle( x, y, radius, seg, color )
	local cir = {}
	surface.SetDrawColor( color )
	draw.NoTexture()
	table.insert( cir, { x = x, y = y, u = 0.5, v = 0.5 } )
	for i = 0, seg do
		local a = math.rad( ( i / seg ) * -360 )
		table.insert( cir, { x = x + math.sin( a ) * radius, y = y + math.cos( a ) * radius, u = math.sin( a ) / 2 + 0.5, v = math.cos( a ) / 2 + 0.5 } )
	end
	local a = math.rad( 0 ) -- This is needed for non absolute segment counts
	table.insert( cir, { x = x + math.sin( a ) * radius, y = y + math.cos( a ) * radius, u = math.sin( a ) / 2 + 0.5, v = math.cos( a ) / 2 + 0.5 } )
	surface.DrawPoly( cir )
end

osuGUI.Materials = {
	cursor = Material( "osu/cursor@2x.png", "noclamp smooth" ),
	cursormiddle = Material( "osu/cursormiddle@2x.png", "noclamp smooth" ),
	cursortrail = Material( "osu/cursortrail@2x.png", "noclamp smooth" ),
	logo_notext = Material( "osu/logo_notext.png", "noclamp smooth" ),
	background = Material( "osu/menu/menu-background@2x.png", "noclamp smooth" ),
	back = Material( "osu/menu/menu-back@2x.png", "noclamp smooth" ),
	hit300 = Material( "osu/playing/hit300@2x.png", "noclamp smooth" ),
	hit100 = Material( "osu/playing/hit100@2x.png", "noclamp smooth" ),
	hit50 = Material( "osu/playing/hit50@2x.png", "noclamp smooth" )
}

osuGUI.BeatSize = 200
osuGUI.Circles = {}
osuGUI.GetHit = function( self, beat ) if !self.Circles[beat] then return false end if self.Circles[beat].Hit then return true end return false end
osuGUI.MouseOver = function( self, beat )
	local x, y = input.GetCursorPos()
	if beat then
		if !self.Circles[beat] then return false end
		if math.Distance( x, y, self.Circles[beat].x, self.Circles[beat].y ) <= (self.BeatSize/4)  then return true end
	else
		for k,v in pairs( self.Circles ) do
			if math.Distance( x, y, v.x, v.y ) <= (self.BeatSize/4)  then return k end 
		end
	end
	return false
end
osuGUI.DrawHit = function( self )
	if !IsValid(self.Map) then return end
	local HitNum = vgui.Create( "DPanel", self.Map )
	local x, y = input.GetCursorPos()
	HitNum:SetPos( x+math.random(10,30), y )
	HitNum:SetSize( 100, 58 )
	// TODO: Implement accuracy.
	local mat = self.Materials[table.Random({"hit300","hit100","hit50"})]
	HitNum.Paint = function( this, w, h )
		surface.SetDrawColor(Color(255,255,255,100))
		surface.SetMaterial( mat )
		surface.DrawTexturedRect(0, 0, w, h)
	end
	HitNum:AlphaTo( 0, 0.5, 0, function(s)
		if IsValid(s) then s:Remove() end
	end)
end
osuGUI.DrawCursor = function( self )
	local x, y = input.GetCursorPos()
	surface.SetDrawColor(color_white)
	surface.SetMaterial( self.Materials.cursor )
	surface.DrawTexturedRect(x-25, y-25, 50, 50)
	surface.SetMaterial( self.Materials.cursormiddle )
	surface.SetDrawColor(Color(255,255,255,100))
	surface.DrawTexturedRect(x-10, y-10, 20, 20)
end
osuGUI.DrawBeat = function( self )
	if !IsValid(self.Map) then return end
	local Beat = OSU.Song.HitObjects[OSU:GetBeat()]
	local scaleAccuracy = 1000
	local scaleX = 512
	local scaleY = 384
	
	local BeatX = tonumber(Beat[1])
	local BeatY = tonumber(Beat[2])
	
	// Convert osu beat vector to screen vector
	local ScrX = Lerp( ( math.Round( BeatX * scaleAccuracy / scaleX ) / scaleAccuracy ), self.BeatSize/4, self.Map:GetWide()-(self.BeatSize/2) )
	local ScrY = Lerp( ( math.Round( BeatY * scaleAccuracy / scaleY ) / scaleAccuracy ), self.BeatSize/4, self.Map:GetTall()-(self.BeatSize/2) )
	
	local offset = 0
	for k,v in pairs( self.Circles ) do
		if !IsValid(v.panel) then continue end
		local pDist = math.Distance( v.x, v.y, ScrX , ScrY )
		offset = pDist
		if pDist > (self.BeatSize/4) then continue end
		ScrX = ScrX+(self.BeatSize/2)
		ScrY = ScrY+(self.BeatSize/2)
		break
	end
	
	local BeatCircle = vgui.Create( "DPanel", self.Map )
	
	self.Circles[OSU:GetBeat()] = {
		x = ScrX, 
		y = ScrY,
		panel = BeatCircle
	}
	
	BeatCircle.Beat = OSU:GetBeat()
	BeatCircle:SetPos( ScrX-(self.BeatSize/2), ScrY-(self.BeatSize/2) )
	BeatCircle:SetSize( self.BeatSize, self.BeatSize )
	local MadeTime = OSU:GetTime()
	local MaxTime = tonumber(Beat[3])
	local Beep = false
	BeatCircle.Paint = function( this, w, h )
		local col = Color( 255, 100, 100, 255 )
		if self:MouseOver(this.Beat) then col = Color( 255, 120, 120, 255 ) end
		if self:GetHit(this.Beat) then
			col = Color( 0, 100, 255, 255 )
		end
		drawCircle( w/2, h/2, w/4, 30, col )
		local CurrentTime = OSU:GetTime()
		local Min = MaxTime-(CurrentTime-MadeTime)
		local check = Lerp( ( math.Round(  Min - MadeTime ) / 1000 ), w/4, w/2 )

		surface.DrawCircle( w/2, h/2, math.Clamp(check,w/4,check), Color( 255, 255, 255, 255 ) )
		surface.DrawCircle( w/2, h/2, math.Clamp(check,w/4,check)-1, Color( 255, 255, 255, 255 ) )
		draw.SimpleText(  this.Beat, "DermaLarge", w/2, h/2, Color(255,255,255,255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
		
		if !Beep and OSU:IsTime(MaxTime) then
			Beep = true
			this:AlphaTo( 0, 0.5, 0, function(s)
				if self.Circles[this.Beat] then self.Circles[this.Beat] = nil end
				if IsValid(s) then s:Remove() end
			end)
			timer.Simple( 0.4, function()
				if IsValid(this) and !self:GetHit(this.Beat) then self:Miss(this.Beat) end
			end)
		end
		
	end
end
osuGUI.Miss = function( self, beat )
	OSU.Combo = 0
	OSU.Health = (OSU.Health - 10)
	surface.PlaySound("osu/combobreak.mp3")
end
osuGUI.Hit = function( self, beat )
	if !self.Circles[beat] then return end
	if self.Circles[beat].Hit then return end
	self.Circles[beat].Hit = true
	surface.PlaySound("osu/hit.mp3")
	osuGUI:DrawHit()
	OSU.Health = math.Clamp(OSU.Health + 140,0,OSU.MaxHealth)
	OSU.Combo = (OSU.Combo + 1)
end
osuGUI.Beat = function( self )
	self:DrawBeat()
end
osuGUI.Fail = function( self )
	if !IsValid(self.Map) then return end
	surface.PlaySound("osu/failsound.mp3")
	local w,h = self.Map:GetSize()
	local x,y = self.Map:GetPos()
	self.Map:AlphaTo(0, 2)
	self.Map:MoveTo( x, y+(h/4), 2, 0, -1, function()
		if IsValid(self.Map) then self.Map:Remove() end
	end )
end
osuGUI.Update = function( self )
	if IsValid(self.HealthBar) then self.HealthBar:SetFraction( (OSU.Health/OSU.MaxHealth) ) end 
end
osuGUI.Start = function( self ) if IsValid(self.Map.Skip) then self.Map.Skip:Remove() end end
osuGUI.Load = function( self )
	if !IsValid(self.Frame) then return end
	self:RenderMap()
end

surface.CreateFont( "Combo", {font="DermaLarge",size = 80,weight = 1500} )
osuGUI.RenderMap = function( self )
	local Map = vgui.Create( "DFrame", self.Frame )
	self.Map = Map
	Map:SetTitle( "" )
	Map:IsKeyboardInputEnabled()
	Map:SetPos( 0, 0 )
	Map:SetSize( self.Frame:GetWide(), self.Frame:GetTall() )
	Map.Paint = function( s, w, h )
		draw.RoundedBox( 0, 0, 0, w, h, Color( 0, 0, 0, 255 ) )
		draw.SimpleText( OSU.Combo.."x", "Combo", 20, h-50, Color(255,255,255,255), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
		
		for k,v in pairs( self.Circles ) do
			local p = self.Circles[k-1] or false
			if p and IsValid(p.panel) and IsValid(v.panel) then
				surface.SetDrawColor( 255, 255, 255, 20 )
				surface.DrawLine( v.x, v.y, p.x, p.y )
			end
		end

	end
	
	local DProgress = vgui.Create( "DProgress", Map )
	self.HealthBar = DProgress
	DProgress:SetPos( 50, 25 )
	DProgress:SetSize( Map:GetWide()-100, 15 )
	DProgress:SetFraction( 1 )
	
	local Skip = vgui.Create( "DButton", Map )
	Map.Skip = Skip
	Skip:SetText( "Skip" )
	Skip:SetPos( Map:GetWide()-150, Map:GetTall()-150 )
	Skip:SetSize( 100, 100 )
	Skip.DoClick = function(this)
		OSU:Skip()
		this:Remove()
	end
	
end
osuGUI.Close = function( self ) OSU:Stop() if !IsValid(self.Frame) then return end self.Frame:AlphaTo( 0, 0.5, 0, function() if IsValid(self.Frame) then self.Frame:Remove() end end) end
osuGUI.OpenFileBrowser = function( self )
	if !IsValid(self.Frame) then return end	
	local Browser = vgui.Create( "DPanel", self.Frame )
	Browser:SetSize( self.Frame:GetWide(), self.Frame:GetTall() )
	Browser.Paint = function( s, w, h )
		draw.RoundedBox( 0, 0, 0, w, h, Color( 0, 0, 0, 240 ) )
	end
	Browser:SetAlpha(0)
	Browser:AlphaTo(255, 0.1)
	local BackButton = vgui.Create( "DButton", Browser )
	BackButton:SetText( "" )
	BackButton:SetSize( 100, 100 )
	BackButton:SetPos( 0, Browser:GetTall()-100 )
	BackButton.DoClick = function(this)
		Browser:Remove()
		surface.PlaySound("osu/click.mp3")
	end
	BackButton.OnCursorEntered = function() surface.PlaySound("osu/roll.mp3") end
	BackButton.Paint = function( s, w, h )
		surface.SetDrawColor(color_white)
		surface.SetMaterial( self.Materials.back )
		surface.DrawTexturedRect(0, 0, w, h)
	end
	local fileList = vgui.Create( "DListView", Browser )
	fileList:SetPos(self.Frame:GetWide()/2,25)
	fileList:SetSize(Browser:GetWide()/2-25, Browser:GetTall()-50)
	fileList:SetMultiSelect( false )
	fileList:AddColumn( "Song Title" )
	fileList.DoDoubleClick = function(this, _, line)
		if !line.path then return end
		surface.PlaySound("osu/play.mp3")
		OSU:Load(line.path)
		Browser:Remove()
	end
	
	// Find osu folders
	local musicFomats = {"mp3","ogg"}
	local _, folders = file.Find(OSU.dataPath .. "*", "DATA")
	for _,v in pairs(folders or {}) do
		local files = file.Find(OSU.dataPath .. "/" .. v .."/*", "DATA")
		local HasMap, HasMusic = false
		for _,f in pairs(files or {}) do
			if string.GetExtensionFromFilename( f ) == "osu" then HasMap = f end
			if table.HasValue( musicFomats, string.GetExtensionFromFilename( f ) ) then HasMusic = f end
		end
		if !HasMap or !HasMusic then continue end
		local song = fileList:AddLine( v )
		song.path = v
		song.OnCursorEntered = function()
			surface.PlaySound("osu/roll.mp3")
		end
	end
end
surface.CreateFont( "OsuTitle", {font="DermaLarge",size = 100,weight = 1500} )
surface.CreateFont( "OsuMENU", {font="DermaLarge",size = 60,weight = 1500} )
osuGUI.Init = function( self )
	local Frame = vgui.Create( "DFrame" )
	self.Frame = Frame
	Frame:SetTitle( "OSU!" )
	Frame:SetSize( ScrW(), ScrH() )
	Frame:MakePopup()
	Frame:SetAlpha(0)
	Frame:AlphaTo(255, 0.2)
	Frame.Paint = function( s, w, h )
		//draw.RoundedBox( 0, 0, 0, w, h, Color( 100, 100, 100, 200 ) )
		surface.SetDrawColor(color_white)
		surface.SetMaterial( self.Materials.background )
		surface.DrawTexturedRect(0, 0, w, h)
		
		surface.SetMaterial( self.Materials.logo_notext )
		surface.DrawTexturedRect(w/2-(w/4), h/2-(w/4), w/2, w/2)
		
		draw.SimpleText( "OSU!", "OsuTitle", w/2, h/2-200, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
		//self:DrawCursor()
	end
	Frame:SetSizable( true )
	
	local Bc = 0
	local function MakeButton(text, action)
		local Button = vgui.Create( "DButton", Frame )
		Button:SetText( "" )
		Button:SetSize( 400, 70 )
		Button:SetPos( ScrW()/2-200, (ScrH()/2)-35+(70*Bc)+15 ) Bc = Bc + 1
		Button.DoClick = function(this)
			surface.PlaySound("osu/click.mp3")
			if action then action(this) end
		end
		Button.OnCursorEntered = function()
			surface.PlaySound("osu/roll.mp3")
		end
		Button.Paint = function( s, w, h )
			local col = Color(100,100,100)
			if s:IsHovered() then col = Color(40,40,40) end
			draw.SimpleTextOutlined( text, "OsuMENU", w/2, h/2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER,1,col )
		end
	end
	
	MakeButton("Select Song", function() self:OpenFileBrowser() end)
	MakeButton("Close", function() self:Close() end)
	
end

concommand.Add("OSU", function()
	OSU:Stop()
	osuGUI:Init()
end)