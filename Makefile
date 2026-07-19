.PHONY: test version

test:
	./scripts/test.sh

## version — show the app version and where to change it.
## Single sources of truth:
##   macOS: ./VERSION (injected into MEditor.app by scripts/bundle.sh)
##   iOS:   MARKETING_VERSION / CURRENT_PROJECT_VERSION in Mobile/MEditorMobile.xcodeproj
version:
	@echo "App version: $$(cat VERSION)"
	@echo "Bump macOS: edit ./VERSION"
	@echo "Bump iOS:   edit MARKETING_VERSION / CURRENT_PROJECT_VERSION in Mobile/MEditorMobile.xcodeproj/project.pbxproj"
