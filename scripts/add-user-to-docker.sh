#!/bin/bash
# Add current user to docker group
# This allows running docker commands without sudo

echo "Adding user $USER to docker group..."
sudo usermod -aG docker $USER

echo ""
echo "✓ User added to docker group"
echo ""
echo "IMPORTANT: You must log out and log back in for this to take effect."
echo ""
echo "Quick option: Run this command to refresh groups in current shell:"
echo "  newgrp docker"
echo ""
echo "Then verify with:"
echo "  docker ps"
