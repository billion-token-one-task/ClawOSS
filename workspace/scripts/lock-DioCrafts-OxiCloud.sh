: "${CLAWOSS_PROJECT_DIR:?Set CLAWOSS_PROJECT_DIR to the ClawOSS project root}"
mkdir -p "$CLAWOSS_PROJECT_DIR/workspace/memory/locks"
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) DioCrafts/OxiCloud#200" > "$CLAWOSS_PROJECT_DIR/workspace/memory/locks/DioCrafts_OxiCloud.lock"
