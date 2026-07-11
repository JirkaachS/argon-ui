-- Argon UI: Rayfield-compatible controls with Orion grouping and WindUI/MacLib styling.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Argon = {Flags={},Version="1.1.1",_connections={},_windows={},_loadingConfig=false,_saveToken=0,_destroyed=false,CurrentTheme="Argon"}

local C = {
    Background=Color3.fromRGB(8,10,16), Window=Color3.fromRGB(13,16,24), Sidebar=Color3.fromRGB(10,13,20),
    Surface=Color3.fromRGB(19,23,33), Hover=Color3.fromRGB(24,29,41), Active=Color3.fromRGB(30,34,48),
    Input=Color3.fromRGB(14,18,27), Border=Color3.fromRGB(44,49,65), BorderSoft=Color3.fromRGB(31,36,49),
    Text=Color3.fromRGB(241,243,249), Muted=Color3.fromRGB(150,157,177), Dim=Color3.fromRGB(98,106,128),
    Accent=Color3.fromRGB(153,112,255), AccentLight=Color3.fromRGB(195,170,255), AccentDark=Color3.fromRGB(92,61,184),
    Success=Color3.fromRGB(74,222,162), Warning=Color3.fromRGB(247,190,79), Danger=Color3.fromRGB(255,101,124),
}

Argon.Themes = {
    Argon={},
    Midnight={Background=Color3.fromRGB(6,9,15),Window=Color3.fromRGB(10,14,23),Sidebar=Color3.fromRGB(7,11,18),Surface=Color3.fromRGB(16,22,34),Hover=Color3.fromRGB(21,29,44),Active=Color3.fromRGB(27,36,54),Input=Color3.fromRGB(10,15,25),Border=Color3.fromRGB(42,53,72),BorderSoft=Color3.fromRGB(28,37,52),Text=Color3.fromRGB(238,244,255),Muted=Color3.fromRGB(146,159,181),Dim=Color3.fromRGB(87,101,126),Accent=Color3.fromRGB(88,166,255),AccentLight=Color3.fromRGB(155,205,255),AccentDark=Color3.fromRGB(35,91,180),Success=Color3.fromRGB(76,220,166),Warning=Color3.fromRGB(247,190,79),Danger=Color3.fromRGB(255,101,124)},
    Emerald={Background=Color3.fromRGB(6,12,11),Window=Color3.fromRGB(10,18,17),Sidebar=Color3.fromRGB(7,15,14),Surface=Color3.fromRGB(16,27,25),Hover=Color3.fromRGB(21,35,32),Active=Color3.fromRGB(27,44,40),Input=Color3.fromRGB(10,20,18),Border=Color3.fromRGB(42,66,60),BorderSoft=Color3.fromRGB(28,46,42),Text=Color3.fromRGB(238,249,246),Muted=Color3.fromRGB(145,171,164),Dim=Color3.fromRGB(87,119,111),Accent=Color3.fromRGB(52,211,153),AccentLight=Color3.fromRGB(151,246,211),AccentDark=Color3.fromRGB(15,118,88),Success=Color3.fromRGB(74,222,162),Warning=Color3.fromRGB(247,190,79),Danger=Color3.fromRGB(255,101,124)},
    Rose={Background=Color3.fromRGB(13,7,11),Window=Color3.fromRGB(21,11,18),Sidebar=Color3.fromRGB(17,8,14),Surface=Color3.fromRGB(31,17,27),Hover=Color3.fromRGB(42,22,35),Active=Color3.fromRGB(54,28,45),Input=Color3.fromRGB(24,12,20),Border=Color3.fromRGB(73,42,61),BorderSoft=Color3.fromRGB(50,29,43),Text=Color3.fromRGB(255,239,248),Muted=Color3.fromRGB(188,148,171),Dim=Color3.fromRGB(132,91,115),Accent=Color3.fromRGB(244,114,182),AccentLight=Color3.fromRGB(251,182,220),AccentDark=Color3.fromRGB(190,24,93),Success=Color3.fromRGB(74,222,162),Warning=Color3.fromRGB(247,190,79),Danger=Color3.fromRGB(255,101,124)},
}
Argon.Themes.Argon={}
for key,value in pairs(C) do Argon.Themes.Argon[key]=value end
Argon.Themes.Amethyst={}
for key,value in pairs(C) do Argon.Themes.Amethyst[key]=value end

local ICONS={activity="◈",swords="⚔",zap="ϟ",move="➤",shirt="◇",pickaxe="◆",["radio-tower"]="⌁",eye="◉",["map-pin"]="⌖",settings="⚙"}

local function safeCall(callback,...)
    if type(callback)~="function" then return end
    local ok,err=pcall(callback,...)
    if not ok then warn("[Argon UI] Callback error: "..tostring(err)) end
end

local function connect(signal,callback)
    local connection=signal:Connect(callback)
    table.insert(Argon._connections,connection)
    return connection
end

local function create(className,props)
    local object=Instance.new(className)
    for property,value in pairs(props or {}) do if property~="Parent" then object[property]=value end end
    if props and props.Parent then object.Parent=props.Parent end
    return object
end

local function corner(parent,radius)
    return create("UICorner",{CornerRadius=UDim.new(0,radius or 10),Parent=parent})
end

local function stroke(parent,color,transparency,thickness)
    return create("UIStroke",{Color=color or C.Border,Transparency=transparency or 0,Thickness=thickness or 1,ApplyStrokeMode=Enum.ApplyStrokeMode.Border,Parent=parent})
end

local function padding(parent,left,right,top,bottom)
    return create("UIPadding",{PaddingLeft=UDim.new(0,left or 0),PaddingRight=UDim.new(0,right or left or 0),PaddingTop=UDim.new(0,top or 0),PaddingBottom=UDim.new(0,bottom or top or 0),Parent=parent})
end

local function gradient(parent,first,second,rotation)
    return create("UIGradient",{Color=ColorSequence.new(first,second),Rotation=rotation or 0,Parent=parent})
end

local function tween(object,duration,props,style,direction)
    local animation=TweenService:Create(object,TweenInfo.new(duration or .18,style or Enum.EasingStyle.Quart,direction or Enum.EasingDirection.Out),props)
    animation:Play()
    return animation
end

local function text(parent,value,size,color,font,props)
    local label=create("TextLabel",{BackgroundTransparency=1,Text=value or "",TextColor3=color or C.Text,TextSize=size or 14,Font=font or Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center,Parent=parent})
    for property,setting in pairs(props or {}) do label[property]=setting end
    return label
end

local function bindCanvas(scroller,layout,extra)
    local function update() scroller.CanvasSize=UDim2.fromOffset(0,layout.AbsoluteContentSize.Y+(extra or 0)) end
    connect(layout:GetPropertyChangedSignal("AbsoluteContentSize"),update)
    update()
end

local function resolveParent()
    local parent
    pcall(function() if gethui then parent=gethui() end end)
    return parent or CoreGui
end

local function copy(value)
    if type(value)~="table" then return value end
    local result={}
    for key,nested in pairs(value) do result[key]=copy(nested) end
    return result
end

local function remapColor(value,oldTheme,newTheme)
    for key,oldColor in pairs(oldTheme) do
        if typeof(oldColor)=="Color3" and value==oldColor and typeof(newTheme[key])=="Color3" then return newTheme[key] end
    end
    return value
end

function Argon:AddTheme(name,palette)
    assert(type(name)=="string" and name~="","Theme name must be a non-empty string")
    assert(type(palette)=="table","Theme palette must be a table")
    local merged=copy(self.Themes.Argon)
    for key,value in pairs(palette) do if typeof(value)=="Color3" then merged[key]=value end end
    self.Themes[name]=merged
    return merged
end

function Argon:GetThemes()
    local names={}
    for name in pairs(self.Themes) do table.insert(names,name) end
    table.sort(names)
    return names
end

function Argon:SetTheme(name)
    local nextTheme=type(name)=="table" and name or self.Themes[tostring(name)]
    if not nextTheme then return false,"Unknown theme: "..tostring(name) end
    local oldTheme=copy(C)
    for _,window in ipairs(self._windows) do
        if window.ScreenGui and window.ScreenGui.Parent then
            for _,object in ipairs(window.ScreenGui:GetDescendants()) do
                if object:IsA("UIGradient") then
                    local points={}
                    for _,point in ipairs(object.Color.Keypoints) do table.insert(points,ColorSequenceKeypoint.new(point.Time,remapColor(point.Value,oldTheme,nextTheme))) end
                    object.Color=ColorSequence.new(points)
                else
                    for _,property in ipairs({"BackgroundColor3","BorderColor3","TextColor3","ImageColor3","ScrollBarImageColor3","Color"}) do
                        pcall(function() object[property]=remapColor(object[property],oldTheme,nextTheme) end)
                    end
                end
            end
        end
    end
    for key,value in pairs(nextTheme) do if typeof(value)=="Color3" then C[key]=value end end
    self.CurrentTheme=type(name)=="string" and name or "Custom"
    return true
end

local function contains(list,value)
    for _,entry in ipairs(list) do if entry==value then return true end end
    return false
end

local function keyName(value)
    if typeof(value)=="EnumItem" then return value.Name end
    local name=tostring(value or "None"):gsub("Enum.KeyCode.","")
    return (name=="" or name=="Unknown") and "None" or name
end

local function configPath()
    local config=Argon._configuration
    if not config or not config.Enabled then return nil end
    local folder=config.FolderName or "ArgonUtility"
    local file=config.FileName or "Argon"
    if not file:match("%.rfld$") then file=file..".rfld" end
    return folder.."/"..file,folder
end

local function scheduleSave()
    if Argon._loadingConfig or Argon._destroyed or not configPath() then return end
    Argon._saveToken+=1
    local token=Argon._saveToken
    task.delay(.35,function() if token==Argon._saveToken and not Argon._destroyed then Argon:SaveConfiguration() end end)
end

local function hover(button,normal,over)
    connect(button.MouseEnter,function() tween(button,.14,{BackgroundColor3=over or C.Hover}) end)
    connect(button.MouseLeave,function() tween(button,.18,{BackgroundColor3=normal or C.Surface}) end)
end

local function registerFlag(flag,element)
    if flag and flag~="" then element.Flag=flag Argon.Flags[flag]=element end
end

local function changed(element)
    if element and element._stroke then
        tween(element._stroke,.12,{Color=C.Accent,Transparency=.12})
        task.delay(.25,function() if element._stroke and element._stroke.Parent then tween(element._stroke,.3,{Color=C.BorderSoft,Transparency=.2}) end end)
    end
    scheduleSave()
end

function Argon:SaveConfiguration()
    local path,folder=configPath()
    if not path or not writefile then return false end
    local data={}
    for flag,element in pairs(self.Flags) do
        if element.Type=="Dropdown" then data[flag]=copy(element.CurrentOption)
        elseif element.Type=="Keybind" then data[flag]=keyName(element.CurrentKeybind or element.CurrentValue)
        elseif element.Type=="ColorPicker" and typeof(element.CurrentValue)=="Color3" then data[flag]={__argonColor=true,R=element.CurrentValue.R,G=element.CurrentValue.G,B=element.CurrentValue.B}
        else data[flag]=copy(element.CurrentValue) end
    end
    return pcall(function()
        if folder and makefolder then pcall(makefolder,folder) end
        writefile(path,HttpService:JSONEncode(data))
    end)
end

function Argon:LoadConfiguration()
    local path=configPath()
    if not path or not readfile or not isfile or not isfile(path) then return false end
    local ok,data=pcall(function() return HttpService:JSONDecode(readfile(path)) end)
    if not ok or type(data)~="table" then return false end
    self._loadingConfig=true
    for flag,value in pairs(data) do
        local element=self.Flags[flag]
        if type(value)=="table" and value.__argonColor then value=Color3.new(tonumber(value.R) or 0,tonumber(value.G) or 0,tonumber(value.B) or 0) end
        if element and element.Set then pcall(function() element:Set(value) end) end
    end
    self._loadingConfig=false
    return true
end

function Argon:Destroy()
    if self._destroyed then return end
    pcall(function() self:SaveConfiguration() end)
    self._destroyed=true
    for _,connection in ipairs(self._connections) do pcall(function() connection:Disconnect() end) end
    for _,window in ipairs(self._windows) do pcall(function() window.ScreenGui:Destroy() end) end
    table.clear(self._connections) table.clear(self._windows) table.clear(self.Flags)
end

function Argon:Notify(options)
    options=options or {}
    local window=self._windows[#self._windows]
    if not window then return end
    local titleValue=tostring(options.Title or "Notification")
    local body=tostring(options.Content or options.Description or "")
    local duration=tonumber(options.Duration) or 4
    local accent=C.Accent
    local lower=titleValue:lower()
    if lower:find("error") or lower:find("failed") then accent=C.Danger
    elseif lower:find("warn") or lower:find("wait") then accent=C.Warning
    elseif lower:find("success") or lower:find("complete") then accent=C.Success end
    local toast=create("Frame",{BackgroundColor3=C.Window,BackgroundTransparency=.03,BorderSizePixel=0,Size=UDim2.fromOffset(338,0),ClipsDescendants=true,ZIndex=100,Parent=window.Notifications})
    corner(toast,13) stroke(toast,C.Border,.12,1)
    local bar=create("Frame",{BackgroundColor3=accent,BorderSizePixel=0,Size=UDim2.fromOffset(3,86),ZIndex=101,Parent=toast}) corner(bar,3)
    local icon=create("TextLabel",{BackgroundColor3=accent,BackgroundTransparency=.84,BorderSizePixel=0,Position=UDim2.fromOffset(15,16),Size=UDim2.fromOffset(34,34),Text="◈",TextColor3=accent,TextSize=17,Font=Enum.Font.GothamBold,ZIndex=101,Parent=toast}) corner(icon,10)
    text(toast,titleValue,13,C.Text,Enum.Font.GothamBold,{Position=UDim2.fromOffset(60,13),Size=UDim2.new(1,-84,0,21),TextTruncate=Enum.TextTruncate.AtEnd,ZIndex=101})
    text(toast,body,12,C.Muted,Enum.Font.Gotham,{Position=UDim2.fromOffset(60,35),Size=UDim2.new(1,-78,0,39),TextWrapped=true,TextYAlignment=Enum.TextYAlignment.Top,ZIndex=101})
    local close=create("TextButton",{AutoButtonColor=false,BackgroundTransparency=1,Position=UDim2.new(1,-27,0,9),Size=UDim2.fromOffset(18,18),Text="×",TextColor3=C.Dim,TextSize=18,Font=Enum.Font.Gotham,ZIndex=102,Parent=toast})
    local progress=create("Frame",{BackgroundColor3=accent,BorderSizePixel=0,Position=UDim2.new(0,3,1,-2),Size=UDim2.new(1,-3,0,2),ZIndex=102,Parent=toast})
    local closed=false
    local function dismiss()
        if closed or not toast.Parent then return end
        closed=true tween(toast,.22,{BackgroundTransparency=1,Size=UDim2.fromOffset(338,0)})
        task.delay(.24,function() if toast then toast:Destroy() end end)
    end
    connect(close.MouseButton1Click,dismiss)
    tween(toast,.24,{Size=UDim2.fromOffset(338,86)},Enum.EasingStyle.Back)
    tween(progress,duration,{Size=UDim2.new(0,0,0,2)},Enum.EasingStyle.Linear)
    task.delay(duration,dismiss)
end

function Argon:CreateWindow(options)
    options=options or {}
    self._destroyed=false
    self._configuration=options.ConfigurationSaving or {Enabled=false}
    if options.Theme then self:SetTheme(options.Theme) end
    local guiParent=resolveParent()
    local existing=guiParent:FindFirstChild("Rayfield")
    if existing then pcall(function() existing:Destroy() end) end
    local gui=create("ScreenGui",{Name="Rayfield",DisplayOrder=100,IgnoreGuiInset=false,ResetOnSpawn=false,ZIndexBehavior=Enum.ZIndexBehavior.Sibling})
    pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)
    gui.Parent=guiParent

    local shadow=create("ImageLabel",{BackgroundTransparency=1,Image="rbxassetid://1316045217",ImageColor3=Color3.new(),ImageTransparency=.28,ScaleType=Enum.ScaleType.Slice,SliceCenter=Rect.new(10,10,118,118),AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(1002,682),ZIndex=1,Parent=gui})
    local main=create("Frame",{Name="ArgonWindow",AnchorPoint=Vector2.new(.5,.5),BackgroundColor3=C.Window,BorderSizePixel=0,ClipsDescendants=true,Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(980,660),ZIndex=2,Parent=gui})
    corner(main,16) stroke(main,C.Border,.08,1) gradient(main,Color3.fromRGB(17,20,31),Color3.fromRGB(10,12,20),115)
    local glowTop=create("Frame",{AnchorPoint=Vector2.new(.5,.5),BackgroundColor3=C.Accent,BackgroundTransparency=.91,BorderSizePixel=0,Position=UDim2.new(1,-95,0,35),Size=UDim2.fromOffset(310,310),ZIndex=2,Parent=main}) corner(glowTop,155)
    local glowBottom=create("Frame",{AnchorPoint=Vector2.new(.5,.5),BackgroundColor3=C.AccentDark,BackgroundTransparency=.95,BorderSizePixel=0,Position=UDim2.new(.35,0,1,80),Size=UDim2.fromOffset(360,360),ZIndex=2,Parent=main}) corner(glowBottom,180)

    local sidebar=create("Frame",{BackgroundColor3=C.Sidebar,BackgroundTransparency=.06,BorderSizePixel=0,Size=UDim2.new(0,232,1,0),ZIndex=3,Parent=main})
    create("Frame",{BackgroundColor3=C.BorderSoft,BackgroundTransparency=.15,BorderSizePixel=0,Position=UDim2.new(1,-1,0,0),Size=UDim2.new(0,1,1,0),Parent=sidebar})
    local brand=create("TextLabel",{BackgroundColor3=C.Accent,BorderSizePixel=0,Position=UDim2.fromOffset(18,17),Size=UDim2.fromOffset(38,38),Text="A",TextColor3=Color3.new(1,1,1),TextSize=17,Font=Enum.Font.GothamBold,Parent=sidebar})
    corner(brand,11) gradient(brand,C.AccentLight,C.AccentDark,135)
    local brandName=text(sidebar,options.Name or "Argon Utility",15,C.Text,Enum.Font.GothamBold,{Position=UDim2.fromOffset(67,17),Size=UDim2.new(1,-82,0,21),TextTruncate=Enum.TextTruncate.AtEnd})
    local brandSub=text(sidebar,"CONTROL CENTER",9,C.Dim,Enum.Font.GothamBold,{Position=UDim2.fromOffset(67,37),Size=UDim2.new(1,-82,0,17)})

    local searchFrame=create("Frame",{BackgroundColor3=C.Input,BorderSizePixel=0,Position=UDim2.fromOffset(14,72),Size=UDim2.new(1,-28,0,38),Parent=sidebar})
    corner(searchFrame,10) stroke(searchFrame,C.BorderSoft,.18,1)
    text(searchFrame,"⌕",17,C.Dim,Enum.Font.Gotham,{Position=UDim2.fromOffset(11,0),Size=UDim2.fromOffset(22,38),TextXAlignment=Enum.TextXAlignment.Center})
    local search=create("TextBox",{BackgroundTransparency=1,ClearTextOnFocus=false,Font=Enum.Font.Gotham,PlaceholderColor3=C.Dim,PlaceholderText="Search this tab",Position=UDim2.fromOffset(37,0),Size=UDim2.new(1,-70,1,0),Text="",TextColor3=C.Text,TextSize=12,TextXAlignment=Enum.TextXAlignment.Left,Parent=searchFrame})
    text(searchFrame,"/",10,C.Dim,Enum.Font.GothamBold,{Position=UDim2.new(1,-27,0,9),Size=UDim2.fromOffset(18,20),TextXAlignment=Enum.TextXAlignment.Center})
    local navCaption=text(sidebar,"NAVIGATION",9,C.Dim,Enum.Font.GothamBold,{Position=UDim2.fromOffset(21,122),Size=UDim2.new(1,-42,0,20)})
    local tabList=create("ScrollingFrame",{Active=true,BackgroundTransparency=1,BorderSizePixel=0,CanvasSize=UDim2.fromOffset(0,0),Position=UDim2.fromOffset(12,146),ScrollBarImageColor3=C.Border,ScrollBarThickness=2,Size=UDim2.new(1,-24,1,-205),Parent=sidebar})
    local tabLayout=create("UIListLayout",{Padding=UDim.new(0,6),SortOrder=Enum.SortOrder.LayoutOrder,Parent=tabList}) bindCanvas(tabList,tabLayout,8)

    local profile=create("Frame",{BackgroundColor3=C.Surface,BackgroundTransparency=.18,BorderSizePixel=0,Position=UDim2.new(0,14,1,-48),Size=UDim2.new(1,-28,0,36),Parent=sidebar}) corner(profile,10)
    local avatar=create("ImageLabel",{BackgroundColor3=C.Active,BorderSizePixel=0,Position=UDim2.fromOffset(5,5),Size=UDim2.fromOffset(26,26),Image="",Parent=profile}) corner(avatar,8)
    pcall(function() avatar.Image=Players:GetUserThumbnailAsync(LocalPlayer.UserId,Enum.ThumbnailType.HeadShot,Enum.ThumbnailSize.Size48x48) end)
    local profileName=text(profile,LocalPlayer and LocalPlayer.DisplayName or "Player",11,C.Text,Enum.Font.GothamMedium,{Position=UDim2.fromOffset(38,2),Size=UDim2.new(1,-44,0,18),TextTruncate=Enum.TextTruncate.AtEnd})
    local profileState=text(profile,"ARGON ONLINE",8,C.Success,Enum.Font.GothamBold,{Position=UDim2.fromOffset(38,17),Size=UDim2.new(1,-44,0,15)})

    local content=create("Frame",{BackgroundTransparency=1,Position=UDim2.fromOffset(232,0),Size=UDim2.new(1,-232,1,0),ZIndex=3,Parent=main})
    local topbar=create("Frame",{BackgroundTransparency=1,Size=UDim2.new(1,0,0,70),Parent=content})
    local eyebrow=text(topbar,"ARGON / DASHBOARD",9,C.AccentLight,Enum.Font.GothamBold,{Position=UDim2.fromOffset(24,14),Size=UDim2.new(1,-150,0,17)})
    local pageTitle=text(topbar,"Dashboard",21,C.Text,Enum.Font.GothamBold,{Position=UDim2.fromOffset(24,29),Size=UDim2.new(1,-160,0,29)})
    local status=create("Frame",{BackgroundColor3=C.Surface,BackgroundTransparency=.14,BorderSizePixel=0,Position=UDim2.new(1,-127,0,19),Size=UDim2.fromOffset(75,28),Parent=topbar}) corner(status,14) stroke(status,C.BorderSoft,.25,1)
    local dot=create("Frame",{BackgroundColor3=C.Success,BorderSizePixel=0,Position=UDim2.fromOffset(10,10),Size=UDim2.fromOffset(7,7),Parent=status}) corner(dot,7)
    text(status,"LIVE",9,C.Muted,Enum.Font.GothamBold,{Position=UDim2.fromOffset(24,0),Size=UDim2.new(1,-29,1,0)})
    local hide=create("TextButton",{AutoButtonColor=false,BackgroundColor3=C.Surface,BackgroundTransparency=.14,BorderSizePixel=0,Position=UDim2.new(1,-43,0,19),Size=UDim2.fromOffset(28,28),Text="–",TextColor3=C.Muted,TextSize=16,Font=Enum.Font.GothamBold,Parent=topbar}) corner(hide,9) stroke(hide,C.BorderSoft,.25,1) hover(hide,C.Surface,C.Hover)
    create("Frame",{BackgroundColor3=C.BorderSoft,BackgroundTransparency=.25,BorderSizePixel=0,Position=UDim2.new(0,24,1,-1),Size=UDim2.new(1,-48,0,1),Parent=topbar})
    local pageHost=create("Frame",{BackgroundTransparency=1,Position=UDim2.fromOffset(0,70),Size=UDim2.new(1,0,1,-70),ClipsDescendants=true,Parent=content})

    local notifications=create("Frame",{AnchorPoint=Vector2.new(1,0),BackgroundTransparency=1,Position=UDim2.new(1,-16,0,16),Size=UDim2.fromOffset(338,500),ZIndex=100,Parent=gui})
    create("UIListLayout",{HorizontalAlignment=Enum.HorizontalAlignment.Right,Padding=UDim.new(0,8),SortOrder=Enum.SortOrder.LayoutOrder,VerticalAlignment=Enum.VerticalAlignment.Top,Parent=notifications})

    local window={ScreenGui=gui,Main=main,Shadow=shadow,Sidebar=sidebar,Content=content,TabList=tabList,PageHost=pageHost,Notifications=notifications,Tabs={},ActiveTab=nil,_visible=true,_toggleKey=options.ToggleUIKeybind or Enum.KeyCode.Insert}
    table.insert(self._windows,window)
    function window:SetVisibility(value)
        self._visible=value~=false
        if not self._visible and self._dropdownPopup then self._dropdownPopup:Destroy() self._dropdownPopup=nil end
        if not self._visible and self._colorPopup then self._colorPopup:Destroy() self._colorPopup=nil end
        gui.Enabled=self._visible
    end
    function window:ToggleVisibility() self:SetVisibility(not self._visible) end
    function window:Open() self:SetVisibility(true) end
    function window:Close() self:SetVisibility(false) end
    function window:Toggle() self:ToggleVisibility() end
    function window:SetToggleKey(value) self._toggleKey=typeof(value)=="EnumItem" and value or Enum.KeyCode[keyName(value)] or self._toggleKey end
    function window:SetTitle(value) brandName.Text=tostring(value or "Argon Utility") end
    function window:SetTheme(value) return Argon:SetTheme(value) end
    function window:GetThemes() return Argon:GetThemes() end
    function window:SetSize(value)
        local width,height
        if typeof(value)=="Vector2" then width,height=value.X,value.Y elseif type(value)=="table" then width,height=value[1] or value.X,value[2] or value.Y end
        width=math.clamp(tonumber(width) or main.AbsoluteSize.X,360,1200) height=math.clamp(tonumber(height) or main.AbsoluteSize.Y,360,820)
        main.Size=UDim2.fromOffset(width,height) shadow.Size=UDim2.fromOffset(width+22,height+22)
    end
    function window:Dialog(config)
        config=config or {}
        local overlay=create("Frame",{Active=true,BackgroundColor3=Color3.new(),BackgroundTransparency=1,BorderSizePixel=0,Size=UDim2.fromScale(1,1),Visible=false,ZIndex=105,Parent=gui})
        local panel=create("Frame",{AnchorPoint=Vector2.new(.5,.5),BackgroundColor3=C.Window,BorderSizePixel=0,Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(380,0),ZIndex=106,Parent=overlay})
        corner(panel,15) stroke(panel,C.Border,.05,1)
        local dialogTitle=text(panel,tostring(config.Title or "Confirm action"),16,C.Text,Enum.Font.GothamBold,{Position=UDim2.fromOffset(20,15),Size=UDim2.new(1,-58,0,24),ZIndex=107})
        local dialogBody=text(panel,tostring(config.Content or config.Description or ""),11,C.Muted,Enum.Font.Gotham,{Position=UDim2.fromOffset(20,47),Size=UDim2.new(1,-40,0,50),TextWrapped=true,TextYAlignment=Enum.TextYAlignment.Top,ZIndex=107})
        local closeButton=create("TextButton",{AutoButtonColor=false,BackgroundTransparency=1,Position=UDim2.new(1,-37,0,13),Size=UDim2.fromOffset(24,24),Text="×",TextColor3=C.Dim,TextSize=19,Font=Enum.Font.Gotham,ZIndex=108,Parent=panel})
        local buttonHost=create("Frame",{BackgroundTransparency=1,Position=UDim2.new(0,20,1,-51),Size=UDim2.new(1,-40,0,34),ZIndex=107,Parent=panel})
        create("UIListLayout",{FillDirection=Enum.FillDirection.Horizontal,HorizontalAlignment=Enum.HorizontalAlignment.Right,Padding=UDim.new(0,8),SortOrder=Enum.SortOrder.LayoutOrder,Parent=buttonHost})
        local dialog={Root=overlay,Panel=panel,Title=dialogTitle,Body=dialogBody,Visible=false}
        function dialog:Close()
            if not self.Root.Parent or not self.Visible then return end
            self.Visible=false tween(overlay,.18,{BackgroundTransparency=1}) tween(panel,.18,{Size=UDim2.fromOffset(380,0)})
            task.delay(.2,function() if overlay.Parent then overlay.Visible=false end end)
        end
        function dialog:Show()
            if not self.Root.Parent then return end
            self.Visible=true overlay.Visible=true panel.Size=UDim2.fromOffset(380,0) overlay.BackgroundTransparency=1
            tween(overlay,.18,{BackgroundTransparency=.38}) tween(panel,.24,{Size=UDim2.fromOffset(380,160)},Enum.EasingStyle.Back)
        end
        function dialog:Destroy() if self.Root then self.Root:Destroy() end end
        connect(closeButton.MouseButton1Click,function() dialog:Close() end)
        local buttons=config.Buttons or {{Title="Okay",Variant="Primary"}}
        for _,buttonConfig in ipairs(buttons) do
            local primary=buttonConfig.Variant=="Primary" or buttonConfig.Primary==true
            local button=create("TextButton",{AutoButtonColor=false,BackgroundColor3=primary and C.Accent or C.Surface,BorderSizePixel=0,Size=UDim2.fromOffset(math.max(82,#tostring(buttonConfig.Title or buttonConfig.Name or "Button")*7+28),34),Text=tostring(buttonConfig.Title or buttonConfig.Name or "Button"),TextColor3=primary and Color3.new(1,1,1) or C.Muted,TextSize=10,Font=Enum.Font.GothamBold,ZIndex=108,Parent=buttonHost})
            corner(button,9) stroke(button,primary and C.Accent or C.BorderSoft,.18,1) hover(button,button.BackgroundColor3,primary and C.AccentLight or C.Hover)
            connect(button.MouseButton1Click,function() safeCall(buttonConfig.Callback,dialog) if buttonConfig.AutoClose~=false then dialog:Close() end end)
        end
        if config.Show~=false then dialog:Show() end
        return dialog
    end
    window.Popup=window.Dialog
    function window:_select(tab)
        if self.ActiveTab==tab then return end
        if self._dropdownPopup then self._dropdownPopup:Destroy() self._dropdownPopup=nil end
        if self._colorPopup then self._colorPopup:Destroy() self._colorPopup=nil end
        if self.ActiveTab then
            self.ActiveTab.Page.Visible=false self.ActiveTab.Accent.Visible=false
            tween(self.ActiveTab.TabButton,.15,{BackgroundTransparency=1,BackgroundColor3=C.Surface})
            tween(self.ActiveTab.IconBox,.15,{BackgroundColor3=C.Active,TextColor3=C.Muted})
            self.ActiveTab.ButtonTitle.TextColor3=C.Muted
        end
        self.ActiveTab=tab tab.Page.Visible=true tab.Accent.Visible=true
        tween(tab.TabButton,.18,{BackgroundTransparency=.05,BackgroundColor3=C.Active})
        tween(tab.IconBox,.18,{BackgroundColor3=C.Accent,TextColor3=Color3.new(1,1,1)})
        tab.ButtonTitle.TextColor3=C.Text pageTitle.Text=tab.Name eyebrow.Text="ARGON / "..tab.Name:upper()
        search.Text="" tab:_filter("")
    end

    function window:CreateTab(name,iconName)
        local tab={Name=tostring(name or "Tab"),Icon=ICONS[tostring(iconName)] or tostring(name or "?"):sub(1,1):upper(),Window=self,_elements={},_sections={},_controlCount=0}
        local button=create("TextButton",{AutoButtonColor=false,BackgroundColor3=C.Surface,BackgroundTransparency=1,BorderSizePixel=0,Size=UDim2.new(1,-4,0,43),Text="",Parent=tabList}) corner(button,10)
        tab.TabButton=button
        tab.Accent=create("Frame",{BackgroundColor3=C.Accent,BorderSizePixel=0,Position=UDim2.fromOffset(0,10),Size=UDim2.fromOffset(2,23),Visible=false,Parent=button}) corner(tab.Accent,2)
        tab.IconBox=create("TextLabel",{BackgroundColor3=C.Active,BackgroundTransparency=.15,BorderSizePixel=0,Position=UDim2.fromOffset(9,7),Size=UDim2.fromOffset(29,29),Text=tab.Icon,TextColor3=C.Muted,TextSize=13,Font=Enum.Font.GothamBold,Parent=button}) corner(tab.IconBox,9)
        tab.ButtonTitle=text(button,tab.Name,12,C.Muted,Enum.Font.GothamMedium,{Position=UDim2.fromOffset(48,0),Size=UDim2.new(1,-78,1,0),TextTruncate=Enum.TextTruncate.AtEnd})
        tab.Count=text(button,"0",9,C.Dim,Enum.Font.GothamBold,{Position=UDim2.new(1,-27,0,0),Size=UDim2.fromOffset(20,43),TextXAlignment=Enum.TextXAlignment.Center})
        local page=create("ScrollingFrame",{Active=true,BackgroundTransparency=1,BorderSizePixel=0,CanvasSize=UDim2.fromOffset(0,0),Position=UDim2.fromOffset(18,14),ScrollBarImageColor3=C.Border,ScrollBarThickness=3,Size=UDim2.new(1,-28,1,-20),Visible=false,Parent=pageHost})
        padding(page,6,12,4,16)
        local pageLayout=create("UIListLayout",{Padding=UDim.new(0,12),SortOrder=Enum.SortOrder.LayoutOrder,Parent=page}) bindCanvas(page,pageLayout,24)
        tab.Page=page

        function tab:_updateCount() self.Count.Text=tostring(self._controlCount) end
        function tab:_filter(query)
            query=tostring(query or ""):lower()
            for _,section in ipairs(self._sections) do
                local visible=0
                for _,element in ipairs(section.Elements) do
                    local match=query=="" or element.Name:lower():find(query,1,true) or section.Name:lower():find(query,1,true)
                    element.Root.Visible=match and true or false if match then visible+=1 end
                end
                section.Root.Visible=visible>0 or query==""
            end
        end

        function tab:CreateSection(sectionName)
            if type(sectionName)=="table" then sectionName=sectionName.Title or sectionName.Name end
            local section={Name=tostring(sectionName or "Section"),Elements={}}
            local root=create("Frame",{BackgroundTransparency=1,Size=UDim2.new(1,-4,0,0),AutomaticSize=Enum.AutomaticSize.Y,Parent=page}) section.Root=root
            local header=create("Frame",{BackgroundTransparency=1,Size=UDim2.new(1,0,0,31),Parent=root})
            local accent=create("Frame",{BackgroundColor3=C.Accent,BorderSizePixel=0,Position=UDim2.fromOffset(1,11),Size=UDim2.fromOffset(3,10),Parent=header}) corner(accent,3)
            text(header,section.Name:upper(),10,C.Muted,Enum.Font.GothamBold,{Position=UDim2.fromOffset(13,0),Size=UDim2.new(1,-13,1,0)})
            local body=create("Frame",{BackgroundColor3=C.Background,BackgroundTransparency=.56,BorderSizePixel=0,Position=UDim2.fromOffset(0,31),Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,Parent=root})
            corner(body,13) stroke(body,C.BorderSoft,.28,1) padding(body,8,8,8,8)
            section.Body=body section.Layout=create("UIListLayout",{Padding=UDim.new(0,7),SortOrder=Enum.SortOrder.LayoutOrder,Parent=body})
            function section:_build(method,...)
                local previous=tab._currentSection tab._currentSection=self
                local result=table.pack(pcall(tab[method],tab,...)) tab._currentSection=previous
                if not result[1] then error(result[2],2) end
                return table.unpack(result,2,result.n)
            end
            for alias,method in pairs({Button="CreateButton",Toggle="CreateToggle",Slider="CreateSlider",Dropdown="CreateDropdown",Input="CreateInput",Keybind="CreateKeybind",Colorpicker="CreateColorPicker",ColorPicker="CreateColorPicker",Paragraph="CreateParagraph",Divider="CreateDivider",Space="CreateSpace"}) do
                local methodName=method
                section[alias]=function(self,...) return self:_build(methodName,...) end
                section[method]=section[alias]
            end
            self._currentSection=section table.insert(self._sections,section)
            return section
        end

        local function base(controlName,height,config)
            if not tab._currentSection then tab:CreateSection("General") end
            local root=create("Frame",{Name="Control",BackgroundColor3=C.Surface,BackgroundTransparency=.08,BorderSizePixel=0,Size=UDim2.new(1,0,0,height or 54),Parent=tab._currentSection.Body}) corner(root,10)
            local element={Name=tostring(controlName or "Control"),Root=root,Section=tab._currentSection,_stroke=stroke(root,C.BorderSoft,.2,1)}
            function element:SetVisible(value) self.Root.Visible=value~=false return self end
            function element:SetTitle(value) self.Name=tostring(value or "Control") if self._title then self._title.Text=self.Name end return self end
            function element:SetDesc(value)
                local description=tostring(value or "")
                if not self._description then
                    self._description=text(root,"",10,C.Dim,Enum.Font.Gotham,{Position=UDim2.fromOffset(14,31),Size=UDim2.new(1,-28,0,18),TextTruncate=Enum.TextTruncate.AtEnd})
                    root.Size=UDim2.new(root.Size.X.Scale,root.Size.X.Offset,0,math.max(root.Size.Y.Offset,68))
                end
                self._description.Text=description self._description.Visible=description~="" return self
            end
            function element:Lock(reason)
                if self._lock then return self end
                local lock=create("TextButton",{Active=true,AutoButtonColor=false,BackgroundColor3=C.Window,BackgroundTransparency=.2,BorderSizePixel=0,Size=UDim2.fromScale(1,1),Text="",ZIndex=28,Parent=root}) corner(lock,10)
                local label=text(lock,"LOCKED"..(reason and reason~="" and " · "..tostring(reason) or ""),9,C.Warning,Enum.Font.GothamBold,{Position=UDim2.new(0,12,0,0),Size=UDim2.new(1,-24,1,0),TextXAlignment=Enum.TextXAlignment.Right,ZIndex=29})
                self._lock={Root=lock,Label=label} self.Locked=true return self
            end
            function element:Unlock() if self._lock then self._lock.Root:Destroy() self._lock=nil end self.Locked=false return self end
            function element:SetTooltip(value)
                self._tooltipText=tostring(value or "")
                if self._tooltipBound then return self end
                self._tooltipBound=true
                connect(root.MouseEnter,function()
                    if self._tooltipText=="" then return end
                    if window._tooltip then window._tooltip:Destroy() end
                    local mouse=UserInputService:GetMouseLocation()
                    local tip=create("TextLabel",{BackgroundColor3=C.Window,BorderSizePixel=0,Position=UDim2.fromOffset(mouse.X+12,mouse.Y+12),Size=UDim2.fromOffset(math.clamp(#self._tooltipText*6+24,110,300),32),Text=self._tooltipText,TextColor3=C.Muted,TextSize=10,Font=Enum.Font.GothamMedium,ZIndex=96,Parent=gui})
                    corner(tip,8) stroke(tip,C.Border,.08,1) window._tooltip=tip
                end)
                connect(root.MouseLeave,function() if window._tooltip then window._tooltip:Destroy() window._tooltip=nil end end)
                return self
            end
            element.Tooltip=element.SetTooltip
            function element:Destroy()
                if self.Root then self.Root:Destroy() end
                for index,item in ipairs(self.Section.Elements) do if item==self then table.remove(self.Section.Elements,index) break end end
                for index,item in ipairs(tab._elements) do if item==self then table.remove(tab._elements,index) break end end
                tab._controlCount=math.max(0,tab._controlCount-1) tab:_updateCount()
            end
            table.insert(tab._currentSection.Elements,element) table.insert(tab._elements,element) tab._controlCount+=1 tab:_updateCount()
            local description=config and (config.Description or config.Desc)
            if description and tostring(description)~="" then element:SetDesc(description) end
            return root,element
        end
        local function title(root,value,width,y)
            return text(root,value,13,C.Text,Enum.Font.GothamMedium,{Position=UDim2.fromOffset(14,y or 0),Size=UDim2.new(1,width or -90,1,0),TextTruncate=Enum.TextTruncate.AtEnd})
        end

        function tab:CreateLabel(value)
            local root,element=base(tostring(value or ""),44) root.BackgroundTransparency=.45 root.AutomaticSize=Enum.AutomaticSize.Y
            local badge=create("TextLabel",{BackgroundColor3=C.Accent,BackgroundTransparency=.84,BorderSizePixel=0,Position=UDim2.fromOffset(11,10),Size=UDim2.fromOffset(24,24),Text="i",TextColor3=C.AccentLight,TextSize=12,Font=Enum.Font.GothamBold,Parent=root}) corner(badge,8)
            local label=text(root,tostring(value or ""),11,C.Muted,Enum.Font.Gotham,{Position=UDim2.fromOffset(44,7),Size=UDim2.new(1,-56,0,30),AutomaticSize=Enum.AutomaticSize.Y,TextWrapped=true})
            element.Type="Label" element.CurrentValue=tostring(value or "")
            function element:Set(nextValue) self.CurrentValue=tostring(nextValue or "") self.Name=self.CurrentValue label.Text=self.CurrentValue end
            return element
        end

        function tab:CreateButton(config)
            config=config or {}
            local root,element=base(config.Name,50,config) element._title=title(root,config.Name or "Button",-70)
            local action=create("TextLabel",{BackgroundColor3=C.Accent,BackgroundTransparency=.84,BorderSizePixel=0,Position=UDim2.new(1,-44,0,9),Size=UDim2.fromOffset(32,32),Text="→",TextColor3=C.AccentLight,TextSize=15,Font=Enum.Font.GothamBold,Parent=root}) corner(action,9)
            local click=create("TextButton",{AutoButtonColor=false,BackgroundTransparency=1,Size=UDim2.fromScale(1,1),Text="",Parent=root}) element.Type="Button"
            connect(click.MouseEnter,function() tween(root,.15,{BackgroundColor3=C.Hover}) tween(action,.15,{BackgroundTransparency=.15,TextColor3=Color3.new(1,1,1)}) end)
            connect(click.MouseLeave,function() tween(root,.18,{BackgroundColor3=C.Surface}) tween(action,.18,{BackgroundTransparency=.84,TextColor3=C.AccentLight}) end)
            connect(click.MouseButton1Click,function() tween(root,.08,{BackgroundColor3=C.Active}) task.delay(.09,function() if root.Parent then tween(root,.16,{BackgroundColor3=C.Hover}) end end) safeCall(config.Callback) end)
            return element
        end

        function tab:CreateToggle(config)
            config=config or {}
            local root,element=base(config.Name,54,config) element._title=title(root,config.Name or "Toggle",-82)
            local track=create("Frame",{BackgroundColor3=C.Input,BorderSizePixel=0,Position=UDim2.new(1,-58,.5,-12),Size=UDim2.fromOffset(44,24),Parent=root}) corner(track,12)
            local knob=create("Frame",{BackgroundColor3=C.Muted,BorderSizePixel=0,Position=UDim2.fromOffset(3,3),Size=UDim2.fromOffset(18,18),Parent=track}) corner(knob,9)
            local click=create("TextButton",{AutoButtonColor=false,BackgroundTransparency=1,Size=UDim2.fromScale(1,1),Text="",Parent=root})
            element.Type="Toggle" element.CurrentValue=config.CurrentValue==true
            local function render(animated)
                local duration=animated and .18 or 0
                if element.CurrentValue then tween(track,duration,{BackgroundColor3=C.Accent}) tween(knob,duration,{Position=UDim2.fromOffset(23,3),BackgroundColor3=Color3.new(1,1,1)})
                else tween(track,duration,{BackgroundColor3=C.Input}) tween(knob,duration,{Position=UDim2.fromOffset(3,3),BackgroundColor3=C.Muted}) end
            end
            function element:Set(value)
                local nextValue=value==true local didChange=self.CurrentValue~=nextValue self.CurrentValue=nextValue render(true)
                if didChange then changed(self) safeCall(config.Callback,self.CurrentValue) end
            end
            connect(click.MouseButton1Click,function() element:Set(not element.CurrentValue) end) hover(root,C.Surface,C.Hover)
            render(false) registerFlag(config.Flag,element) return element
        end

        function tab:CreateSlider(config)
            config=config or {}
            local range=config.Range or {0,100} local minimum=tonumber(range[1]) or 0 local maximum=tonumber(range[2]) or 100 local increment=tonumber(config.Increment) or 1
            local root,element=base(config.Name,72,config) element._title=title(root,config.Name or "Slider",-100,-13)
            local valueBox=create("TextBox",{BackgroundColor3=C.Input,BorderSizePixel=0,ClearTextOnFocus=false,Font=Enum.Font.GothamBold,Position=UDim2.new(1,-73,0,9),Size=UDim2.fromOffset(59,26),Text="0",TextColor3=C.AccentLight,TextSize=10,Parent=root}) corner(valueBox,8) stroke(valueBox,C.BorderSoft,.25,1)
            local bar=create("Frame",{Active=true,BackgroundColor3=C.Input,BorderSizePixel=0,Position=UDim2.fromOffset(14,51),Size=UDim2.new(1,-28,0,5),Parent=root}) corner(bar,4)
            local fill=create("Frame",{BackgroundColor3=C.Accent,BorderSizePixel=0,Size=UDim2.new(0,0,1,0),Parent=bar}) corner(fill,4) gradient(fill,C.AccentLight,C.AccentDark,0)
            local handle=create("Frame",{AnchorPoint=Vector2.new(.5,.5),BackgroundColor3=Color3.new(1,1,1),BorderSizePixel=0,Position=UDim2.fromScale(0,.5),Size=UDim2.fromOffset(13,13),Parent=bar}) corner(handle,7) stroke(handle,C.Accent,0,2)
            element.Type="Slider" element.CurrentValue=tonumber(config.CurrentValue) or minimum
            local function round(value)
                value=math.clamp(value,minimum,maximum) value=math.floor((value-minimum)/increment+.5)*increment+minimum
                local decimals=tostring(increment):match("%.(%d+)") if decimals then local power=10^#decimals value=math.floor(value*power+.5)/power end
                return math.clamp(value,minimum,maximum)
            end
            local function render()
                local ratio=maximum==minimum and 0 or (element.CurrentValue-minimum)/(maximum-minimum)
                fill.Size=UDim2.new(ratio,0,1,0) handle.Position=UDim2.new(ratio,0,.5,0) valueBox.Text=tostring(element.CurrentValue)..(config.Suffix or "")
            end
            function element:Set(value)
                local parsed=tonumber(value) or tonumber(tostring(value):match("[-%d%.]+")) if not parsed then render() return end
                local nextValue=round(parsed) local didChange=self.CurrentValue~=nextValue self.CurrentValue=nextValue render()
                if didChange then changed(self) safeCall(config.Callback,self.CurrentValue) end
            end
            local draggingSlider=false
            local function fromX(x) local ratio=math.clamp((x-bar.AbsolutePosition.X)/math.max(1,bar.AbsoluteSize.X),0,1) element:Set(minimum+(maximum-minimum)*ratio) end
            connect(bar.InputBegan,function(input) if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then draggingSlider=true fromX(input.Position.X) end end)
            connect(UserInputService.InputChanged,function(input) if draggingSlider and (input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch) then fromX(input.Position.X) end end)
            connect(UserInputService.InputEnded,function(input) if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then draggingSlider=false end end)
            connect(valueBox.FocusLost,function() element:Set(valueBox.Text) end) hover(root,C.Surface,C.Hover)
            element.CurrentValue=round(element.CurrentValue) render() registerFlag(config.Flag,element) return element
        end

        function tab:CreateInput(config)
            config=config or {}
            local root,element=base(config.Name,70,config)
            element._title=text(root,config.Name or "Input",11,C.Muted,Enum.Font.GothamMedium,{Position=UDim2.fromOffset(14,4),Size=UDim2.new(1,-28,0,20)})
            local input=create("TextBox",{BackgroundColor3=C.Input,BorderSizePixel=0,ClearTextOnFocus=false,Font=Enum.Font.Gotham,PlaceholderColor3=C.Dim,PlaceholderText=config.PlaceholderText or "Enter value...",Position=UDim2.fromOffset(13,28),Size=UDim2.new(1,-26,0,31),Text=tostring(config.CurrentValue or ""),TextColor3=C.Text,TextSize=11,TextXAlignment=Enum.TextXAlignment.Left,Parent=root})
            corner(input,9) padding(input,11,11,0,0) local inputStroke=stroke(input,C.BorderSoft,.22,1)
            element.Type="Input" element.CurrentValue=tostring(config.CurrentValue or "")
            function element:Set(value)
                local nextValue=tostring(value or "") local didChange=self.CurrentValue~=nextValue self.CurrentValue=nextValue input.Text=nextValue
                if didChange then changed(self) safeCall(config.Callback,nextValue) end
            end
            connect(input.Focused,function() tween(inputStroke,.15,{Color=C.Accent,Transparency=0}) end)
            connect(input.FocusLost,function()
                tween(inputStroke,.18,{Color=C.BorderSoft,Transparency=.22}) element:Set(input.Text)
                if config.RemoveTextAfterFocusLost then input.Text="" end
            end)
            registerFlag(config.Flag,element) return element
        end

        function tab:CreateKeybind(config)
            config=config or {}
            local root,element=base(config.Name,54,config) element._title=title(root,config.Name or "Keybind",-105)
            local bind=create("TextButton",{AutoButtonColor=false,BackgroundColor3=C.Input,BorderSizePixel=0,Position=UDim2.new(1,-91,.5,-14),Size=UDim2.fromOffset(77,28),Text="None",TextColor3=C.AccentLight,TextSize=10,Font=Enum.Font.GothamBold,Parent=root}) corner(bind,8) stroke(bind,C.BorderSoft,.24,1)
            element.Type="Keybind" element.CurrentKeybind=keyName(config.CurrentKeybind) element.CurrentValue=element.CurrentKeybind
            local listening=false
            local function render() bind.Text=listening and "PRESS KEY" or element.CurrentKeybind bind.TextColor3=listening and C.Warning or C.AccentLight end
            function element:Set(value)
                local nextValue=keyName(value) local didChange=self.CurrentKeybind~=nextValue self.CurrentKeybind=nextValue self.CurrentValue=nextValue listening=false render()
                if didChange then changed(self) safeCall(config.Callback,nextValue) end
            end
            connect(bind.MouseButton1Click,function() listening=not listening render() end)
            connect(UserInputService.InputBegan,function(input,processed)
                if not listening or processed or input.UserInputType~=Enum.UserInputType.Keyboard then return end
                if input.KeyCode==Enum.KeyCode.Escape or input.KeyCode==Enum.KeyCode.Backspace then element:Set("None") else element:Set(input.KeyCode.Name) end
            end)
            hover(root,C.Surface,C.Hover) render() registerFlag(config.Flag,element) return element
        end

        function tab:CreateDropdown(config)
            config=config or {}
            local multiple=config.MultipleOptions==true
            local root,element=base(config.Name,58,config)
            element._title=text(root,config.Name or "Dropdown",11,C.Muted,Enum.Font.GothamMedium,{Position=UDim2.fromOffset(14,5),Size=UDim2.new(.45,-18,0,20),TextTruncate=Enum.TextTruncate.AtEnd})
            local selectButton=create("TextButton",{AutoButtonColor=false,BackgroundColor3=C.Input,BorderSizePixel=0,Position=UDim2.new(.45,0,0,10),Size=UDim2.new(.55,-14,0,37),Text="",Parent=root}) corner(selectButton,9)
            local selectStroke=stroke(selectButton,C.BorderSoft,.22,1)
            local selectedText=text(selectButton,"Select...",10,C.Text,Enum.Font.GothamMedium,{Position=UDim2.fromOffset(10,0),Size=UDim2.new(1,-35,1,0),TextTruncate=Enum.TextTruncate.AtEnd})
            text(selectButton,"⌄",14,C.Dim,Enum.Font.GothamBold,{Position=UDim2.new(1,-27,0,0),Size=UDim2.fromOffset(22,37),TextXAlignment=Enum.TextXAlignment.Center})
            element.Type="Dropdown" element.Options=copy(config.Options or {}) element.CurrentOption={}
            local initial=config.CurrentOption
            if type(initial)=="table" then element.CurrentOption=copy(initial) elseif initial~=nil and tostring(initial)~="" then element.CurrentOption={initial} end
            if not multiple and #element.CurrentOption>1 then element.CurrentOption={element.CurrentOption[1]} end
            element.CurrentValue=element.CurrentOption
            local function render()
                if #element.CurrentOption==0 then selectedText.Text="Select..." selectedText.TextColor3=C.Dim
                elseif multiple and #element.CurrentOption>2 then selectedText.Text=tostring(element.CurrentOption[1]).."  +"..tostring(#element.CurrentOption-1) selectedText.TextColor3=C.Text
                else
                    local parts={} for _,value in ipairs(element.CurrentOption) do table.insert(parts,tostring(value)) end
                    selectedText.Text=table.concat(parts,", ") selectedText.TextColor3=C.Text
                end
            end
            function element:Set(value)
                local nextSelection={}
                if type(value)=="table" then
                    for _,entry in ipairs(value) do if contains(self.Options,entry) then table.insert(nextSelection,entry) if not multiple then break end end end
                elseif contains(self.Options,value) then nextSelection={value} end
                local before=HttpService:JSONEncode(self.CurrentOption) self.CurrentOption=nextSelection self.CurrentValue=nextSelection render()
                if before~=HttpService:JSONEncode(nextSelection) then changed(self) safeCall(config.Callback,copy(nextSelection)) end
            end
            function element:Refresh(newOptions,keepCurrent)
                self.Options=copy(newOptions or {}) local retained={}
                if keepCurrent~=false then for _,selected in ipairs(self.CurrentOption) do if contains(self.Options,selected) then table.insert(retained,selected) end end end
                self.CurrentOption=retained self.CurrentValue=retained render()
            end
            local function closePopup()
                if window._dropdownPopup then window._dropdownPopup:Destroy() window._dropdownPopup=nil end
                tween(selectStroke,.15,{Color=C.BorderSoft,Transparency=.22})
            end
            local function openPopup()
                closePopup()
                local absolute=selectButton.AbsolutePosition local popupWidth=math.max(210,selectButton.AbsoluteSize.X)
                local viewport=workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920,1080)
                local x=math.clamp(absolute.X,8,viewport.X-popupWidth-8)
                local popup=create("Frame",{BackgroundColor3=C.Window,BorderSizePixel=0,Position=UDim2.fromOffset(x,absolute.Y+selectButton.AbsoluteSize.Y+6),Size=UDim2.fromOffset(popupWidth,0),ZIndex=80,Parent=gui})
                window._dropdownPopup=popup corner(popup,12) stroke(popup,C.Border,.02,1)
                local filter=create("TextBox",{BackgroundColor3=C.Input,BorderSizePixel=0,ClearTextOnFocus=false,Font=Enum.Font.Gotham,PlaceholderColor3=C.Dim,PlaceholderText="Filter options...",Position=UDim2.fromOffset(9,9),Size=UDim2.new(1,-18,0,32),Text="",TextColor3=C.Text,TextSize=10,TextXAlignment=Enum.TextXAlignment.Left,ZIndex=81,Parent=popup}) corner(filter,8) padding(filter,10,10,0,0)
                local list=create("ScrollingFrame",{Active=true,BackgroundTransparency=1,BorderSizePixel=0,CanvasSize=UDim2.fromOffset(0,0),Position=UDim2.fromOffset(8,49),ScrollBarImageColor3=C.Border,ScrollBarThickness=2,Size=UDim2.new(1,-16,1,-57),ZIndex=81,Parent=popup})
                local layout=create("UIListLayout",{Padding=UDim.new(0,4),SortOrder=Enum.SortOrder.LayoutOrder,Parent=list}) bindCanvas(list,layout,5)
                local records={}
                for _,option in ipairs(element.Options) do
                    local optionText=tostring(option) local selected=contains(element.CurrentOption,option)
                    local choice=create("TextButton",{AutoButtonColor=false,BackgroundColor3=selected and C.Active or C.Surface,BackgroundTransparency=.08,BorderSizePixel=0,Size=UDim2.new(1,-4,0,32),Text=optionText,TextColor3=selected and C.AccentLight or C.Muted,TextSize=10,Font=Enum.Font.GothamMedium,TextXAlignment=Enum.TextXAlignment.Left,ZIndex=82,Parent=list})
                    padding(choice,11,11,0,0) corner(choice,8) hover(choice,choice.BackgroundColor3,C.Hover) table.insert(records,{Button=choice,Text=optionText:lower()})
                    connect(choice.MouseButton1Click,function()
                        if multiple then
                            local nextSelection=copy(element.CurrentOption)
                            if contains(nextSelection,option) then for index,value in ipairs(nextSelection) do if value==option then table.remove(nextSelection,index) break end end else table.insert(nextSelection,option) end
                            element:Set(nextSelection) local active=contains(element.CurrentOption,option) choice.BackgroundColor3=active and C.Active or C.Surface choice.TextColor3=active and C.AccentLight or C.Muted
                        else element:Set({option}) closePopup() end
                    end)
                end
                connect(filter:GetPropertyChangedSignal("Text"),function()
                    local query=filter.Text:lower() for _,record in ipairs(records) do record.Button.Visible=query=="" or record.Text:find(query,1,true)~=nil end
                end)
                tween(selectStroke,.15,{Color=C.Accent,Transparency=0}) tween(popup,.2,{Size=UDim2.fromOffset(popupWidth,226)},Enum.EasingStyle.Back)
            end
            connect(selectButton.MouseButton1Click,function() if window._dropdownPopup then closePopup() else openPopup() end end)
            render() registerFlag(config.Flag,element) return element
        end

        function tab:CreateParagraph(config)
            if type(config)~="table" then config={Title="Information",Content=tostring(config or "")} end
            local root,element=base(config.Title or config.Name,68)
            local badge=create("TextLabel",{BackgroundColor3=C.Accent,BackgroundTransparency=.84,BorderSizePixel=0,Position=UDim2.fromOffset(12,13),Size=UDim2.fromOffset(30,30),Text=tostring(config.Icon or "i"),TextColor3=C.AccentLight,TextSize=13,Font=Enum.Font.GothamBold,Parent=root}) corner(badge,9)
            element._title=text(root,tostring(config.Title or config.Name or "Information"),12,C.Text,Enum.Font.GothamBold,{Position=UDim2.fromOffset(53,8),Size=UDim2.new(1,-65,0,21),TextTruncate=Enum.TextTruncate.AtEnd})
            local contentLabel=text(root,tostring(config.Content or config.Description or ""),10,C.Muted,Enum.Font.Gotham,{Position=UDim2.fromOffset(53,29),Size=UDim2.new(1,-65,0,30),TextWrapped=true,TextYAlignment=Enum.TextYAlignment.Top})
            element.Type="Paragraph" element.CurrentValue=contentLabel.Text
            function element:Set(value) self.CurrentValue=tostring(value or "") contentLabel.Text=self.CurrentValue end
            function element:SetContent(value) self:Set(value) return self end
            return element
        end

        function tab:CreateDivider(config)
            local labelValue=type(config)=="table" and (config.Title or config.Name) or config
            local root,element=base(labelValue or "Divider",labelValue and 29 or 15)
            root.BackgroundTransparency=1 element._stroke.Transparency=1
            create("Frame",{AnchorPoint=Vector2.new(0,.5),BackgroundColor3=C.BorderSoft,BackgroundTransparency=.18,BorderSizePixel=0,Position=UDim2.new(0,4,.5,0),Size=labelValue and UDim2.new(.34,-8,0,1) or UDim2.new(1,-8,0,1),Parent=root})
            if labelValue then
                element._title=text(root,tostring(labelValue):upper(),9,C.Dim,Enum.Font.GothamBold,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.new(.3,0,1,0),TextXAlignment=Enum.TextXAlignment.Center})
                create("Frame",{AnchorPoint=Vector2.new(1,.5),BackgroundColor3=C.BorderSoft,BackgroundTransparency=.18,BorderSizePixel=0,Position=UDim2.new(1,-4,.5,0),Size=UDim2.new(.34,-8,0,1),Parent=root})
            end
            element.Type="Divider" return element
        end

        function tab:CreateSpace(size)
            local root,element=base("Space",math.clamp(tonumber(size) or 10,4,80))
            root.BackgroundTransparency=1 element._stroke.Transparency=1 element.Type="Space" return element
        end

        function tab:CreateColorPicker(config)
            config=config or {}
            local root,element=base(config.Name,58,config)
            element._title=text(root,config.Name or "Color picker",12,C.Text,Enum.Font.GothamMedium,{Position=UDim2.fromOffset(14,0),Size=UDim2.new(1,-108,1,0),TextTruncate=Enum.TextTruncate.AtEnd})
            local swatch=create("TextButton",{AutoButtonColor=false,BackgroundColor3=typeof(config.Color)=="Color3" and config.Color or typeof(config.CurrentValue)=="Color3" and config.CurrentValue or C.Accent,BorderSizePixel=0,Position=UDim2.new(1,-94,.5,-15),Size=UDim2.fromOffset(80,30),Text="",Parent=root})
            corner(swatch,9) local swatchStroke=stroke(swatch,C.Border,.08,1)
            local hexLabel=text(swatch,"#000000",9,Color3.new(1,1,1),Enum.Font.GothamBold,{Size=UDim2.fromScale(1,1),TextXAlignment=Enum.TextXAlignment.Center})
            element.Type="ColorPicker" element.CurrentValue=swatch.BackgroundColor3
            local function hex(color) return string.format("#%02X%02X%02X",math.floor(color.R*255+.5),math.floor(color.G*255+.5),math.floor(color.B*255+.5)) end
            local function parseHex(value)
                local clean=tostring(value or ""):gsub("#","")
                if #clean~=6 then return nil end
                local number=tonumber(clean,16) if not number then return nil end
                return Color3.fromRGB(math.floor(number/65536)%256,math.floor(number/256)%256,number%256)
            end
            local function render() swatch.BackgroundColor3=element.CurrentValue hexLabel.Text=hex(element.CurrentValue) end
            function element:Set(value)
                local color=typeof(value)=="Color3" and value or parseHex(value) if not color then return end
                local didChange=self.CurrentValue~=color self.CurrentValue=color render()
                if didChange then changed(self) safeCall(config.Callback,color) end
            end
            local function closePicker()
                if window._colorPopup then window._colorPopup:Destroy() window._colorPopup=nil end
                tween(swatchStroke,.15,{Color=C.Border,Transparency=.08})
            end
            local function openPicker()
                closePicker() if window._dropdownPopup then window._dropdownPopup:Destroy() window._dropdownPopup=nil end
                local h,s,v=element.CurrentValue:ToHSV() local absolute=swatch.AbsolutePosition
                local popup=create("Frame",{BackgroundColor3=C.Window,BorderSizePixel=0,Position=UDim2.fromOffset(absolute.X-170,absolute.Y+38),Size=UDim2.fromOffset(250,0),ZIndex=84,Parent=gui})
                window._colorPopup=popup corner(popup,12) stroke(popup,C.Border,.02,1) padding(popup,10,10,10,10)
                local square=create("Frame",{Active=true,BackgroundColor3=Color3.fromHSV(h,1,1),BorderSizePixel=0,Position=UDim2.fromOffset(10,10),Size=UDim2.new(1,-20,0,116),ZIndex=85,Parent=popup}) corner(square,8)
                local white=create("Frame",{BackgroundColor3=Color3.new(1,1,1),BorderSizePixel=0,Size=UDim2.fromScale(1,1),ZIndex=86,Parent=square}) corner(white,8) gradient(white,Color3.new(1,1,1),Color3.new(1,1,1),0).Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(1,1)})
                local black=create("Frame",{BackgroundColor3=Color3.new(),BorderSizePixel=0,Size=UDim2.fromScale(1,1),ZIndex=87,Parent=square}) corner(black,8) gradient(black,Color3.new(),Color3.new(),90).Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(1,0)})
                local cursor=create("Frame",{AnchorPoint=Vector2.new(.5,.5),BackgroundColor3=Color3.new(1,1,1),BorderSizePixel=0,Position=UDim2.fromScale(s,1-v),Size=UDim2.fromOffset(11,11),ZIndex=88,Parent=square}) corner(cursor,6) stroke(cursor,Color3.new(),.2,2)
                local hue=create("Frame",{Active=true,BackgroundColor3=Color3.new(1,1,1),BorderSizePixel=0,Position=UDim2.fromOffset(10,136),Size=UDim2.new(1,-20,0,13),ZIndex=85,Parent=popup}) corner(hue,7)
                create("UIGradient",{Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromHSV(0,1,1)),ColorSequenceKeypoint.new(.17,Color3.fromHSV(.17,1,1)),ColorSequenceKeypoint.new(.33,Color3.fromHSV(.33,1,1)),ColorSequenceKeypoint.new(.5,Color3.fromHSV(.5,1,1)),ColorSequenceKeypoint.new(.67,Color3.fromHSV(.67,1,1)),ColorSequenceKeypoint.new(.83,Color3.fromHSV(.83,1,1)),ColorSequenceKeypoint.new(1,Color3.fromHSV(1,1,1))}),Parent=hue})
                local hueCursor=create("Frame",{AnchorPoint=Vector2.new(.5,.5),BackgroundColor3=Color3.new(1,1,1),BorderSizePixel=0,Position=UDim2.fromScale(h,.5),Size=UDim2.fromOffset(7,19),ZIndex=87,Parent=hue}) corner(hueCursor,4) stroke(hueCursor,Color3.new(),.2,1)
                local hexBox=create("TextBox",{BackgroundColor3=C.Input,BorderSizePixel=0,ClearTextOnFocus=false,Font=Enum.Font.GothamBold,Position=UDim2.fromOffset(10,159),Size=UDim2.new(1,-20,0,31),Text=hex(element.CurrentValue),TextColor3=C.Text,TextSize=10,ZIndex=86,Parent=popup}) corner(hexBox,8) stroke(hexBox,C.BorderSoft,.2,1)
                local draggingSquare=false local draggingHue=false
                local function updateSquare(x,y) s=math.clamp((x-square.AbsolutePosition.X)/math.max(1,square.AbsoluteSize.X),0,1) v=1-math.clamp((y-square.AbsolutePosition.Y)/math.max(1,square.AbsoluteSize.Y),0,1) cursor.Position=UDim2.fromScale(s,1-v) element:Set(Color3.fromHSV(h,s,v)) hexBox.Text=hex(element.CurrentValue) end
                local function updateHue(x) h=math.clamp((x-hue.AbsolutePosition.X)/math.max(1,hue.AbsoluteSize.X),0,1) hueCursor.Position=UDim2.fromScale(h,.5) square.BackgroundColor3=Color3.fromHSV(h,1,1) element:Set(Color3.fromHSV(h,s,v)) hexBox.Text=hex(element.CurrentValue) end
                connect(square.InputBegan,function(input) if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then draggingSquare=true updateSquare(input.Position.X,input.Position.Y) end end)
                connect(hue.InputBegan,function(input) if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then draggingHue=true updateHue(input.Position.X) end end)
                connect(UserInputService.InputChanged,function(input) if draggingSquare then updateSquare(input.Position.X,input.Position.Y) elseif draggingHue then updateHue(input.Position.X) end end)
                connect(UserInputService.InputEnded,function(input) if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then draggingSquare=false draggingHue=false end end)
                connect(hexBox.FocusLost,function() element:Set(hexBox.Text) hexBox.Text=hex(element.CurrentValue) end)
                tween(swatchStroke,.15,{Color=C.Accent,Transparency=0}) tween(popup,.2,{Size=UDim2.fromOffset(250,201)},Enum.EasingStyle.Back)
            end
            connect(swatch.MouseButton1Click,function() if window._colorPopup then closePicker() else openPicker() end end)
            render() registerFlag(config.Flag,element) return element
        end
        tab.Colorpicker=tab.CreateColorPicker
        tab.ColorPicker=tab.CreateColorPicker
        tab.Button=tab.CreateButton
        tab.Toggle=tab.CreateToggle
        tab.Slider=tab.CreateSlider
        tab.Dropdown=tab.CreateDropdown
        tab.Input=tab.CreateInput
        tab.Keybind=tab.CreateKeybind
        tab.Paragraph=tab.CreateParagraph
        tab.Divider=tab.CreateDivider
        tab.Space=tab.CreateSpace
        tab.Section=tab.CreateSection

        local compactNow=sidebar.AbsoluteSize.X<100
        tab.ButtonTitle.Visible=not compactNow tab.Count.Visible=not compactNow
        connect(button.MouseButton1Click,function() window:_select(tab) end) hover(button,C.Surface,C.Hover)
        table.insert(self.Tabs,tab) if not self.ActiveTab then self:_select(tab) end
        return tab
    end

    local dragging=false local dragStart local startPosition
    connect(topbar.InputBegan,function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then dragging=true dragStart=input.Position startPosition=main.Position end
    end)
    connect(UserInputService.InputChanged,function(input)
        if dragging and (input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch) then
            local delta=input.Position-dragStart main.Position=UDim2.new(startPosition.X.Scale,startPosition.X.Offset+delta.X,startPosition.Y.Scale,startPosition.Y.Offset+delta.Y) shadow.Position=main.Position
        end
    end)
    connect(UserInputService.InputEnded,function(input) if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then dragging=false end end)
    connect(hide.MouseButton1Click,function() window:SetVisibility(false) end)
    connect(search:GetPropertyChangedSignal("Text"),function() if window.ActiveTab then window.ActiveTab:_filter(search.Text) end end)
    connect(UserInputService.InputBegan,function(input,processed)
        if processed then return end
        if input.KeyCode==window._toggleKey then window:ToggleVisibility()
        elseif input.KeyCode==Enum.KeyCode.Slash and window._visible then search:CaptureFocus() end
    end)

    local function responsive()
        local camera=workspace.CurrentCamera if not camera then return end
        local viewport=camera.ViewportSize local width=math.clamp(viewport.X-28,360,980) local height=math.clamp(viewport.Y-42,420,660)
        main.Size=UDim2.fromOffset(width,height) shadow.Size=UDim2.fromOffset(width+22,height+22)
        local compact=width<760 local sideWidth=compact and 72 or 232
        sidebar.Size=UDim2.new(0,sideWidth,1,0) content.Position=UDim2.fromOffset(sideWidth,0) content.Size=UDim2.new(1,-sideWidth,1,0)
        brandName.Visible=not compact brandSub.Visible=not compact brand.Position=UDim2.fromOffset(compact and 17 or 18,17)
        searchFrame.Visible=not compact navCaption.Visible=not compact profileName.Visible=not compact profileState.Visible=not compact
        profile.Size=compact and UDim2.fromOffset(42,36) or UDim2.new(1,-28,0,36) profile.Position=compact and UDim2.new(0,15,1,-48) or UDim2.new(0,14,1,-48)
        avatar.Position=compact and UDim2.fromOffset(8,5) or UDim2.fromOffset(5,5)
        tabList.Position=UDim2.fromOffset(compact and 11 or 12,compact and 72 or 146) tabList.Size=UDim2.new(1,compact and -18 or -24,1,compact and -132 or -205)
        for _,tab in ipairs(window.Tabs) do tab.ButtonTitle.Visible=not compact tab.Count.Visible=not compact end
        status.Visible=width>=620
    end
    connect(workspace:GetPropertyChangedSignal("CurrentCamera"),responsive)
    if workspace.CurrentCamera then connect(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"),responsive) end
    responsive()

    local splash=create("Frame",{BackgroundColor3=C.Window,BorderSizePixel=0,Size=UDim2.fromScale(1,1),ZIndex=120,Parent=main})
    local splashMark=create("TextLabel",{AnchorPoint=Vector2.new(.5,.5),BackgroundColor3=C.Accent,BorderSizePixel=0,Position=UDim2.fromScale(.5,.43),Size=UDim2.fromOffset(58,58),Text="A",TextColor3=Color3.new(1,1,1),TextSize=24,Font=Enum.Font.GothamBold,ZIndex=121,Parent=splash}) corner(splashMark,17) gradient(splashMark,C.AccentLight,C.AccentDark,135)
    text(splash,options.LoadingTitle or options.Name or "Argon Utility",17,C.Text,Enum.Font.GothamBold,{AnchorPoint=Vector2.new(.5,0),Position=UDim2.fromScale(.5,.51),Size=UDim2.fromOffset(320,26),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=121})
    text(splash,options.LoadingSubtitle or "Preparing interface...",10,C.Dim,Enum.Font.GothamMedium,{AnchorPoint=Vector2.new(.5,0),Position=UDim2.fromScale(.5,.555),Size=UDim2.fromOffset(320,20),TextXAlignment=Enum.TextXAlignment.Center,ZIndex=121})
    task.delay(.55,function()
        if not splash.Parent then return end
        tween(splash,.28,{BackgroundTransparency=1}) tween(splashMark,.28,{BackgroundTransparency=1,TextTransparency=1})
        for _,child in ipairs(splash:GetChildren()) do if child:IsA("TextLabel") and child~=splashMark then tween(child,.22,{TextTransparency=1}) end end
        task.delay(.3,function() if splash then splash:Destroy() end end)
    end)
    return window
end

return Argon
