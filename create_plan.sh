#!/bin/bash
set -e

# =======================================================
# .ENV ファイルの読み込み
# =======================================================

# .env ファイルが存在する場合、内容を環境変数として読み込む
if [ -f .env ]; then
    echo "--- .envファイルを読み込み、環境変数を設定中 ---"
    # whileループを使用して、コメント行と空行をスキップし、
    # 残りのKEY=VALUE形式の行を export する
    while IFS= read -r line || [[ -n "$line" ]]; do
        # コメント行 (#) または空行をスキップ
        [[ "$line" =~ ^#.* ]] && continue
        [[ -z "$line" ]] && continue
        
        # 変数をエクスポート (例: export RESOURCE_GROUP="takeo")
        export "$line"
    done < .env
else
    echo "エラー: .envファイルが見つかりません。処理を中断します。" >&2
    exit 1
fi

az appservice plan create \
  --name "$APP_PLAN" \
  --resource-group "$RESOURCE_GROUP" \
  --sku B1 \
  --is-linux \
  --tags $TAGS