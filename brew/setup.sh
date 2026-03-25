/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Automatic updates every 24 hours with upgrade and cleanup
brew tap homebrew/autoupdate
brew autoupdate start --upgrade --cleanup

