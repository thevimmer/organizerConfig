local os = require("os")

local organizerPath = os.getenv("HOME") .. "/Organizer"
local organizerHomePagePath = organizerPath .. "/home.wiki"
local organizerGroup = vim.api.nvim_create_augroup("Organizer", {})

-- [[ Calendar ]]
local calendarFirstLineNumber = 11

local function organizerGenerateCalendar()
	local calendar = {}
	local calendarWidth = 20

	local currentDate = os.date("*t")
	local currentYear = currentDate.year
	local currentMonth = currentDate.month

	local firstDay = os.date("*t", os.time({ year = currentYear, month = currentMonth, day = 1 })).wday
	firstDay = firstDay - 1 --NOTE adjust so that Monday = 1, Sunday = 7
	if firstDay == 0 then
		firstDay = 7
	end

	local calendarHeader = os.date("%B %Y", os.time({ year = currentYear, month = currentMonth, day = 1 }))
	local calendarHeaderPadding = math.floor((calendarWidth - #calendarHeader) / 2) + 1
	table.insert(calendar, string.rep(" ", calendarHeaderPadding) .. calendarHeader)
	table.insert(calendar, "Mo Tu We Th Fr Sa Su")

	local weekLine = ""
	for _ = 1, firstDay - 1 do
		weekLine = weekLine .. "   "
	end

	local daysInMonth = os.date("*t", os.time({ year = currentYear, month = currentMonth + 1, day = 0 })).day

	local dayOfWeek = firstDay
	for day = 1, daysInMonth do
		local dayTxt = string.format("%02d", day)
		local yearTxt = string.sub(tostring(currentYear), -2)
		local monthTxt = string.format("%02d", currentMonth)

		local dayLink = string.format("[[%s/%s/%s|%s]]", yearTxt, monthTxt, dayTxt, dayTxt)
		weekLine = weekLine .. " " .. dayLink

		if dayOfWeek == 7 then
			table.insert(calendar, weekLine:sub(2)) --NOTE remove leading space
			weekLine = ""
			dayOfWeek = 1
		else
			dayOfWeek = dayOfWeek + 1
		end
	end

	--NOTE add the remaining days of the last week
	if weekLine ~= "" then
		table.insert(calendar, weekLine:sub(2))
	end

	return calendar
end

local function organizerUpdateCalendar()
	if vim.b.calendarUpdated then
		return
	end

	local calendar = organizerGenerateCalendar()

	local homePageContent = {}
	do
		local homePage = io.open(organizerHomePagePath, "r")
		if not homePage then
			print("Failed to open organizer's home page for reading")
			return
		end
		for line in homePage:lines() do
			table.insert(homePageContent, line)
		end
		homePage:close()
	end

	for i, line in ipairs(calendar) do
		homePageContent[calendarFirstLineNumber + i - 1] = line:gsub("%s+$", "")
	end

	do
		local tempFilePath = organizerHomePagePath .. ".tmp"
		local tempFile = io.open(tempFilePath, "w")
		if not tempFile then
			print("Failed to open a temporary file for writing")
			return
		end
		for _, line in ipairs(homePageContent) do
			tempFile:write(line, "\n")
		end
		tempFile:close()
		os.remove(organizerHomePagePath)
		os.rename(tempFilePath, organizerHomePagePath)
	end

	vim.cmd("checktime")
	vim.b.calendarUpdated = true
end

vim.api.nvim_create_autocmd("BufReadPre", {
	pattern = organizerHomePagePath,
	callback = organizerUpdateCalendar,
	desc = "Update the calendar before the buffer is read",
	group = organizerGroup,
})

vim.api.nvim_create_user_command("OrganizerUpdateCalendar", function()
	vim.b.calendarUpdated = false
	organizerUpdateCalendar()
end, {})

-- [[ Todos ]]

--ADD a section in the day page associated to checked todos
local function organizerArchiveCheckedTodos()
	local homePageContent = {}
	do
		local homePage = io.open(organizerHomePagePath, "r")
		if not homePage then
			print("Failed to open organizer home page for reading")
			return
		end
		for line in homePage:lines() do
			table.insert(homePageContent, line)
		end
		homePage:close()
	end

	--ADD check only the todos section (starts at line 19)
	local updatedTodos = {}
	local archivedTodos = {}
	for _, line in ipairs(homePageContent) do
		if line:match("^%* %[X%]") then
			table.insert(archivedTodos, line)
		else
			table.insert(updatedTodos, line)
		end
	end

	do
		local tempFilePath = organizerHomePagePath .. ".tmp"
		local tempFile = io.open(tempFilePath, "w")
		if not tempFile then
			print("Failed to open a temporary file for writing.")
			return
		end
		for _, line in ipairs(updatedTodos) do
			tempFile:write(line .. "\n")
		end
		tempFile:close()
		os.remove(organizerHomePagePath)
		os.rename(tempFilePath, organizerHomePagePath)
	end

	local currentDate = os.date("*t")
	local currentDay = currentDate.day
	local currentMonth = currentDate.month
	local currentYearFormated = string.sub(tostring(currentDate.year), -2)

	local todayPagePath = organizerPath
		.. string.format("%s/%02d/%02d", currentYearFormated, currentMonth, currentDay)
		.. ".wiki"
	if #archivedTodos > 0 then
		local todayPage = io.open(todayPagePath, "a")
		if not todayPage then
			print("Failed to open today's page for appending.")
			return
		end

		for _, line in ipairs(archivedTodos) do
			todayPage:write(string.gsub(line, "%* %[X%] ", "") .. "\n")
		end

		todayPage:close()
	end

	vim.cmd("checktime")
end

vim.api.nvim_create_autocmd("BufWritePost", {
	pattern = organizerHomePagePath,
	callback = organizerArchiveCheckedTodos,
	group = organizerGroup,
})

vim.api.nvim_create_user_command("OrganizerArchiveCheckedTodos", organizerArchiveCheckedTodos, {})

-- [[ Sync ]]
local function organizerSync()
	vim.cmd("G add .")

	local commitMessage = vim.fn.input("Commit message: ")

	vim.cmd('G commit -m "' .. commitMessage .. '"')

	vim.cmd("G push --set-upstream origin master")
end

vim.api.nvim_create_autocmd("Filetype", {
	pattern = "wiki",
	callback = function()
		vim.api.keymap.set("n", "<leader>gs", organizerSync, { desc = "Sync with the remote repo" })
	end,
	group = organizerGroup,
})

--FIX it doesn't work
vim.api.nvim_create_user_command("OrganizerSync", organizerSync, {})
