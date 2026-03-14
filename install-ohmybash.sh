#!/usr/bin/env bash

set -e

echo "Checking requirements..."

if ! command -v git >/dev/null 2>&1; then
    echo "Git is not installed."

    read -p "Install git now? (y/n): " answer

    if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
        echo "Installing git..."

        if command -v apt >/dev/null; then
            sudo apt update
            sudo apt install -y git
        elif command -v dnf >/dev/null; then
            sudo dnf install -y git
        elif command -v pacman >/dev/null; then
            sudo pacman -Sy git
        else
            echo "Unsupported package manager. Please install git manually."
            exit 1
        fi
    else
        echo "Git is required. Exiting."
        exit 1
    fi
fi

echo "Git found."

echo "Installing Oh My Bash..."

bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh)"

echo "Installation complete!"
