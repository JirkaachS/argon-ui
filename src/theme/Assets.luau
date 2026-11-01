--!nocheck
-- Image assets. The shadow and glow roles use v1's public soft-shadow 9-slice. DESIGN_V2 2.10
-- specifies dedicated "hollow" images (a ring whose hole matches the window); they are not made
-- or uploaded yet, and adopting them means new ids here plus the hollow placement offsets.

return {
	shadow = { Image = "rbxassetid://1316045217", SliceCenter = Rect.new(10, 10, 118, 118) },
	glow = { Image = "rbxassetid://1316045217", SliceCenter = Rect.new(10, 10, 118, 118) },
	cursor = "rbxasset://textures/Cursors/KeyboardMouse/ArrowFarCursor.png",
}
