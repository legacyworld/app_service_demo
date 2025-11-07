#!/bin/zsh

DOTENV_FILE="./.env"

typeset -A APP_SETTINGS

if [ -f "$DOTENV_FILE" ]; then
    echo "--- .envファイルを読み込み、環境変数を設定中 ---"
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # コメント行 (#) または空行をスキップ
        [[ "$line" =~ ^[[:space:]]*#.* ]] && continue
        [[ -z "$line" ]] && continue

        # KEY=VALUE形式を解析（=を複数含む値にも対応）
        KEY=$(echo "$line" | cut -d'=' -f1 | xargs)
        VALUE=$(echo "$line" | cut -d'=' -f2- | xargs)
        export "$KEY=$VALUE"

        # 連想配列に登録
        APP_SETTINGS[$KEY]="$VALUE"
    done < "$DOTENV_FILE"
else
    echo "エラー: .envファイルが見つかりません。処理を中断します。" >&2
    exit 1
fi

echo "Resource Group: $RESOURCE_GROUP"
echo "Web App Name: $WEB_APP_NAME"
echo "------------------------------------------------"

# ----------------------------------------------------
# 3. JSON 形式で Azure CLI に渡すための一時ファイルを作成
# ----------------------------------------------------
TMP_JSON_FILE=$(mktemp /tmp/appsettings.XXXXXX.json)

# JSON出力用バッファを初期化
JSON_CONTENT="{"
for KEY in ${(k)APP_SETTINGS}; do
  VALUE="${APP_SETTINGS[$KEY]}"
  # 値の中のダブルクォートをエスケープ
  ESCAPED_VALUE="${VALUE//\"/\\\"}"
  JSON_CONTENT+="\"$KEY\":\"$ESCAPED_VALUE\","
done

# 動的な設定追加
DEPLOY_ID="$(date +%Y%m%d%H%M%S)"
GIT_COMMIT="initial-deploy"
JSON_CONTENT+="\"DEPLOY_ID\":\"$DEPLOY_ID\",\"GIT_COMMIT\":\"$GIT_COMMIT\""

JSON_CONTENT+="}"

# JSONファイルに保存
echo "$JSON_CONTENT" > "$TMP_JSON_FILE"

echo "--- App Settings JSON ---"
cat "$TMP_JSON_FILE"
echo "--------------------------"

# ----------------------------------------------------
# 4. Azure CLI コマンド実行（JSONファイル指定）
# ----------------------------------------------------
az webapp config appsettings set \
  --resource-group "$RESOURCE_GROUP" \
  --name "$WEB_APP_NAME" \
  --settings @"$TMP_JSON_FILE"

STATUS=$?

# 一時ファイル削除
rm -f "$TMP_JSON_FILE"

if [ $STATUS -eq 0 ]; then
    echo "✅ Deployment settings applied successfully."
else
    echo "❌ Failed to apply app settings (status: $STATUS)"
    exit 1
fi
