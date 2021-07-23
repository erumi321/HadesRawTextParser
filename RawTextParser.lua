local keyCodeToId = {
	["UP"] = "Up",
	["DN"] = "Down",
	["LT"] = "Left",
	["RT"] = "Right",
	["A1"] = "Attack1",
	["A2"] = "Attack2",
	["A3"] = "Attack3",
	["RU"] = "Rush",
	["AL"] = "AutoLock",
	["SL"] = "Select",
	["CF"] = "Confirm",
	["CT"] = "ContinueText",
	["CN"] = "Cancel",
	["ML"] = "MenuLeft",
	["MR"] = "MenuRight",
	["MU"] = "MenuUp",
	["MD"] = "MenuDown",
	["SH"] = "Shout",
	["AS"] = "Assist",
	["AT"] = "AdvancedTooltip",
	["I"] = "Use",
	["G"] = "Gift",
	["RL"] = "Reload",
	["EM"] = "Emote",
	["ST"] = "Pause",
	["CX"] = "Codex",
	["RF"] = "ReportFeedback",
	["TS"] = "TakeScreenshot",
}
--Returns textbox args with parsed raw text (no sjson formatting while still being parsed)
--will return a table of textbox args, but they will all have position 0,0 (may be changed later if i figure out how to calculate text width, not hard with monospaced 
--but not everything is monospaced)
function TextBoxToRawTextBox(args, RawStringArgs)
	if args.Text == nil and args.RawText == nil then
		DebugPrint({Text = "@TextBoxToRawtextBox, Error: No Text or RawText provided"})
		return args
	end

	local strings = BuildRawStrings(args, RawStringArgs or {})

	--build the textbox args
	local builtTextboxes = {}
	for k,v in pairs(strings) do
		local newTextbox = DeepCopyTable(args)
		newTextbox.Text = nil
		newTextbox.RawText = v.Text
		if v.Format ~= nil and v.Format ~= {} then
			CombineTables(newTextbox, v.Format)
		end
		table.insert(builtTextboxes, newTextbox)
	end
	return builtTextboxes
end

function TextBoxToRawString(args, singleLine, RawStringArgs)
	local rawStrings = BuildRawStrings(args, RawStringArgs or {})
	if singleLine then
		local returnString = ""
		for k,v in pairs(rawStrings) do
			returnString = returnString .. v.Text
		end
		return returnString
	else
		return rawStrings
	end
end

--@param textboxArgs - takes the textbox args that would be passed into CreateTextBox
--@param args - takes extra args related to the function into place (see below)
	--@arg AllowIcons - Prevents icons from being replaced by text (will not affect keyboard control icons)
	--@arg AllowSpecificIcons - Allows icons by names in table to be displayed as icons and not as text (use table not array so {"...", "...", "..."})
	--@arg RemoveIcons - Removes all icons and doesn't display their text
	--@arg RemoveIconExemptions - Table of names of icons that RemoveIcons will not remove (use table not array so {"...", "...", "..."})
	--@arg AllowDoubleIcons - If enabled Icons in the DisplayName of Icons in the base text will not be removed (is useless if AllowIcons is on)
	--@arg AllowControllIcons - Prevent controll icons from being replaced by text (will not affect non-control text icons)
	--@arg IgnoreFormats - Ignores creating overriding formats
function BuildRawStrings(textboxArgs, args)
	--get the inputted text to parse
	local pureText = textboxArgs.Text or textboxArgs.RawText
	--Get the sjson
	local sjsonText = GetDisplayName({Text = pureText, GetDescription = textboxArgs.UseDescription})

	--parse it with the custom parser
	local parsedText = sjsonText:LuaRawTextParse()
	--will contain a list of all raw text strings as well as overrideing formats to put into a textbox RawText field
	local builtStrings = {}
	local currentStringIndex = 1

	if tostring(pureText):find("Signoff") then
		DebugPrint({Text = sjsonText})
	end

	for k,v in pairs(parsedText) do
		if builtStrings[currentStringIndex] == nil then
			builtStrings[currentStringIndex] = {Text = ""}
		end
		if v:sub(1,1) == "{" then
			local commandPrefix = v:sub(2,2)
			-- $ - DisplayName of a Lua variable with VariableAutoFormat formatting (minus exceptions from NeverFormat table)
			if commandPrefix == "$" then
				local variableName = v:sub(3)
				local isPercent = false

				--If the name has a suffix like :P remove it
				if #RawTextSplit(variableName, ":", false) > 1 then
					variableName = RawTextSplit(variableName, ":", false)[1]
					if RawTextSplit(v:sub(3), ":", false)[2] == "P" then
						isPercent = true
					end
				end

				local value = _G[variableName]

				if RawTextSplit(variableName, ".", false)[1] == "Keywords" then
					value = GetDisplayName({Text = value})
				end

				--If not in the global namespace check the LuaValue for values, or if its TooltipData / TempTextData, which damage value doesn't update for some reason
				if textboxArgs.LuaValue ~= nil and value == nil or (RawTextSplit(variableName, ".", false)[1] == "TooltipData" or RawTextSplit(variableName, ".", false)[1] == "TempTextData") then
					if textboxArgs.LuaValue.NewTotal1 == "PercentNewTotal1" then
						isPercent = true
					end
					if textboxArgs.LuaValue.NewTotal ~= nil then
						textboxArgs.LuaValue.NewTotal1 = textboxArgs.LuaValue.NewTotal[1]
						textboxArgs.LuaValue.Total1 = textboxArgs.LuaValue.NewTotal[1]
						textboxArgs.LuaValue.DisplayDelta1 = textboxArgs.LuaValue.NewTotal[1]
					end
					value = textboxArgs.LuaValue[RawTextSplit(variableName, ".", false)[2]]
				end
				--If damage value is still nil fall back and take from the tooltip /temp text (hopefully never happens)
				if value == nil and (RawTextSplit(variableName, ".", false)[1] == "TooltipData" or RawTextSplit(variableName, ".", false)[1] == "TempTextData") then
					value = _G[variableName]
				end
				if isPercent == true then
					value = value .. "%"
				end
				if type(value) ~= "table" then
					builtStrings[currentStringIndex].Text = builtStrings[currentStringIndex].Text .. " " .. (value or ("{@TextBoxToRawtextBox, Error: " .. variableName .. " is nil}"))
				end
			-- ! - Texture of the path stored in a Lua variable (icons), currently just subsitutes it for name based on icon
			elseif commandPrefix == "!" and (args.RemoveIcons ~= true or Contains(args.RemoveIconExemptions, RawTextSplit(v:sub(3), ".", false)[2])) then
				local iconName = RawTextSplit(v:sub(3), ".", false)[2]
				if iconName:sub(#iconName - 5, #iconName) == "_Small" then
					iconName = iconName:sub(1, #iconName - 6)
				elseif iconName:sub(#iconName - 4, #iconName) == "Small" then
					iconName = iconName:sub(1, #iconName - 5)
				end
				local iconDisplayName = GetDisplayName({Text = iconName})
				
				--Remove icons in the icon name
				if iconDisplayName:find("{!Icons.") and args.AllowDoubleIcons ~= true then
					iconDisplayName = RawTextSplit(iconDisplayName, "}", false)[2]
				end

				if args.AllowIcons or Contains(args.AllowSpecificIcons, iconName) then
					iconDisplayName = "{!" .. v:sub(3) .. "}"
				end
				if iconDisplayName:sub(#iconDisplayName - 5, #iconDisplayName) == "_Small" then
					iconDisplayName = iconDisplayName:sub(1, #iconDisplayName - 6)
				end
				if iconDisplayName:sub(#iconDisplayName - 4, #iconDisplayName) == "Small" then
					iconDisplayName = iconDisplayName:sub(1, #iconDisplayName - 5)
				end
				builtStrings[currentStringIndex].Text = builtStrings[currentStringIndex].Text .. " " .. iconDisplayName  .. " "
			-- # - Formatting stored in TextFormats.[ForamtName] in UIData.lua skip this if its the last item so if PreviousFormat is last an empty value isn't made
			elseif commandPrefix == "#" and k < #parsedText and args.IgnoreFormats ~= true then
				if v:sub(3) == "PreviousFormat" then
					--create new string with former format
					currentStringIndex = currentStringIndex + 1
					builtStrings[currentStringIndex] = {Text = ""}
				else
					--create new string with new format
					currentStringIndex = currentStringIndex + 1
					builtStrings[currentStringIndex] = {Text = "", Format = {}}
					builtStrings[currentStringIndex].Format = TextFormats[v:sub(3)]
				end
			elseif keyCodeToId[v:sub(2,3)] ~= nil then
				if args.AllowControllIcons then
					builtStrings[currentStringIndex].Text = builtStrings[currentStringIndex].Text .. "{" .. v:sub(2,3) .. "}"
				else
					builtStrings[currentStringIndex].Text = builtStrings[currentStringIndex].Text .. GetDisplayName({Text = keyCodeToId[v:sub(2,3)]})
				end
			end
		else
			builtStrings[currentStringIndex].Text = builtStrings[currentStringIndex].Text .. v
		end
	end
	return builtStrings
end

--Parses sjson text into a table of individual commands (normal strings and the special variables)
function string.LuaRawTextParse(input)
	local splitSections = {}
	local tempSplit = RawTextSplit(input, "{", true)
	local extraInsertedAmount = 0
	for k,v in pairs(tempSplit) do
		--split by end Bracket so special commands inside curly brakcets are their own table values
		local splitEndBracket = RawTextSplit(v, "}", false)
		for i,t in pairs(splitEndBracket) do
			if i - 1 > 0 then
				extraInsertedAmount = extraInsertedAmount + 1
			end
			table.insert(splitSections, k + extraInsertedAmount, t)
		end
	end
	return splitSections
end

--https://stackoverflow.com/questions/1426954/split-string-in-lua
--modified to allow including seperator
function RawTextSplit(inputstr, sep, includeSep)
	if sep == nil then
			sep = "%s"
	end
	local t={}
	for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
		local newStr = str
		if (#t > 0 and includeSep) or (includeSep and #t == 0 and inputstr:sub(1,1) == sep) then
			newStr = sep .. str
		end
		table.insert(t, newStr)
	end
	return t
end