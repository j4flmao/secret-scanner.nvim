.PHONY: test lint fmt fmt-check

test:
	nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

lint:
	luacheck lua/

fmt:
	stylua lua/ plugin/ tests/

fmt-check:
	stylua --check lua/ plugin/ tests/
