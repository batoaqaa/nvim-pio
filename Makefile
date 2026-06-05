# Force Lua to check our local project directory on Windows PowerShell
test:
	@set "LUA_PATH=$(CURDIR)/lua/?.lua;$(CURDIR)/lua/?/init.lua;;;" && nvim --headless -c "PlenaryBustedDirectory spec/"

.PHONY: test
