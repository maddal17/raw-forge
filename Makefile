.PHONY: build test install run clean

build:
	@bash Scripts/build.sh

test: build

install: build
	@if [ -w "/Applications" ]; then \
		rm -rf "/Applications/RawForge.app"; \
		cp -R dist/RawForge.app "/Applications/RawForge.app"; \
		echo "Installed to /Applications/RawForge.app"; \
	else \
		mkdir -p "$(HOME)/Applications"; \
		rm -rf "$(HOME)/Applications/RawForge.app"; \
		cp -R dist/RawForge.app "$(HOME)/Applications/RawForge.app"; \
		echo "Installed to $(HOME)/Applications/RawForge.app"; \
	fi

run: build
	@open dist/RawForge.app

clean:
	@rm -rf .build dist
