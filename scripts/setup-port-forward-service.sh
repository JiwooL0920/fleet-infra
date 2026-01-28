#!/bin/bash
# Setup automatic port forwarding as a macOS LaunchAgent

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLIST_PATH="$HOME/Library/LaunchAgents/com.fleet-infra.port-forward.plist"

echo "=== Fleet-Infra Port Forward Service Setup ==="
echo ""

# Create the LaunchAgent plist
cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.fleet-infra.port-forward</string>
    
    <key>ProgramArguments</key>
    <array>
        <string>${SCRIPT_DIR}/port-forward.sh</string>
    </array>
    
    <key>RunAtLoad</key>
    <true/>
    
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    
    <key>StandardOutPath</key>
    <string>${HOME}/.cursor/projects/Users-jiwoolee-Project-fleet-infra/terminals/port-forward.log</string>
    
    <key>StandardErrorPath</key>
    <string>${HOME}/.cursor/projects/Users-jiwoolee-Project-fleet-infra/terminals/port-forward.err</string>
    
    <key>ThrottleInterval</key>
    <integer>10</integer>
</dict>
</plist>
EOF

echo "✅ Created LaunchAgent: $PLIST_PATH"
echo ""
echo "To enable the service:"
echo "  launchctl load $PLIST_PATH"
echo ""
echo "To disable the service:"
echo "  launchctl unload $PLIST_PATH"
echo ""
echo "To check status:"
echo "  launchctl list | grep fleet-infra"
echo ""
echo "To view logs:"
echo "  tail -f ${HOME}/.cursor/projects/Users-jiwoolee-Project-fleet-infra/terminals/port-forward.log"
