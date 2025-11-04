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

# =======================================================
# 1. 環境設定
# =======================================================

# --- ハードコードされていた設定を削除し、.envから読み込んだ変数を使用 ---

# --- タグ設定 (これは引き続きスクリプト内に維持) ---
TAGS="division=field org=sa team=apj-japan project=takeofurukubo keep-until=2025-11-01"

# 変数の確認（読み込みに失敗した場合に備えてチェック）
if [ -z "$WEB_APP_NAME" ] || [ -z "$RESOURCE_GROUP" ] || [ -z "$REGION" ]; then
    echo "エラー: 必須の環境変数 (WEB_APP_NAME, RESOURCE_GROUP, REGION) のいずれかが.envから読み込めませんでした。" >&2
    exit 1
fi

echo "========================================"
echo "Azure App Service デプロイ開始"
echo "WebApp Name: $WEB_APP_NAME"
echo "Resource Group: $RESOURCE_GROUP"
echo "========================================"

# =======================================================
# 2. Azure リソースの作成
# =======================================================

# echo "--- 1. リソースグループの作成 ---"
# az group create --name "$RESOURCE_GROUP" --location "$REGION" --tags $TAGS

echo "--- 2. App Service Plan の作成 (B1 SKU) ---"
# az appservice plan create \
#   --name "$APP_PLAN" \
#   --resource-group "$RESOURCE_GROUP" \
#   --sku B1 \
#   --is-linux \
#   --tags $TAGS

echo "--- 3. Web App の作成 (Python 3.10) ---"
az webapp create \
  --resource-group "$RESOURCE_GROUP" \
  --plan "$APP_PLAN" \
  --name "$WEB_APP_NAME" \
  --runtime "PYTHON|3.10" \
  --tags $TAGS

echo "--- 4. Gunicorn 起動コマンドの設定 ---"
az webapp config set \
  --resource-group "$RESOURCE_GROUP" \
  --name "$WEB_APP_NAME" \
  --startup-file "opentelemetry.sh"

echo "--- 5. 環境変数の設定 (SLOW/ERROR Rate, メタデータ) ---"
# SLOW_RATE, ERROR_RATE, DEPLOY_ID は .env から読み込んだ値を使用
az webapp config appsettings set \
  --resource-group "$RESOURCE_GROUP" \
  --name "$WEB_APP_NAME" \
  --settings SLOW_RATE="$SLOW_RATE" ERROR_RATE="$ERROR_RATE" GIT_COMMIT="initial-deploy" DEPLOY_ID="$(date +%Y%m%d%H%M%S)" REDIS_HOST="$REDIS_NAME.redis.cache.windows.net" REDIS_PASSWORD="$REDIS_PASSWORD"

# OTLP設定も .env から読み込んだシークレットを使用
az webapp config appsettings set \
  --resource-group "$RESOURCE_GROUP" \
  --name "$WEB_APP_NAME" \
  --settings \
    OTEL_METRICS_EXPORTER="otlp" \
    OTEL_EXPORTER_OTLP_ENDPOINT=$OTEL_EXPORTER_OTLP_ENDPOINT \
    OTEL_LOGS_EXPORTER="otlp" \
    OTEL_EXPORTER_OTLP_HEADERS=$OTEL_EXPORTER_OTLP_HEADERS \
    OTEL_RESOURCE_ATTRIBUTES=$OTEL_RESOURCE_ATTRIBUTES \
    OTEL_PYTHON_LOG_CORRELATION=$OTEL_PYTHON_LOG_CORRELATION \
    OTEL_PYTHON_LOGGING_AUTO_INSTRUMENTATION_ENABLED=$OTEL_PYTHON_LOGGING_AUTO_INSTRUMENTATION_ENABLED

# =======================================================
# 3. Git デプロイの実行
# =======================================================

echo "--- 7. ローカル Git リポジトリの準備 ---"
# 既存の.gitディレクトリが存在する場合は削除 (ユーザーの指示に基づき、クリーンな状態にする)
if [ -d ".git" ]; then
    echo "  -> 既存のGitリポジトリ(.git)を削除しています..."
    rm -rf .git
fi

# Gitリポジトリが存在しない場合（削除された後、または最初からなかった場合）に初期化
if [ ! -d ".git" ]; then
    echo "  -> Gitリポジトリを初期化..."
    git init -b main
fi
# ファイルが追跡されているか確認し、コミット
# (ここでは、ファイルが存在しない場合の動作を防ぐため、存在チェックを追加することが望ましいが、元のスクリプトを踏襲)
# if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1 || git status --porcelain | grep -q '??'; then
#     git add app.py requrements.txt templates/ || true # ファイルが存在しない場合もエラーにしない
#     git commit -m "Initial commit for App Service deployment" || true
# fi

echo "--- 8. App Service Git エンドポイント設定 ---"
GIT_URL="https://$WEB_APP_NAME.scm.azurewebsites.net/$WEB_APP_NAME.git"

az webapp deployment source config-local-git \
  --name "$WEB_APP_NAME" \
  --resource-group "$RESOURCE_GROUP"

# リモート設定
# 既に存在する場合はエラーになるため、一旦削除してから追加するロジックを追加
if git remote get-url azure > /dev/null 2>&1; then
    git remote remove azure
fi
git remote add azure "$GIT_URL"

az webapp config appsettings set --resource-group "$RESOURCE_GROUP" --name "$WEB_APP_NAME" --settings DEPLOYMENT_BRANCH=main

# =======================================================
# 4. 完了
# =======================================================

echo "========================================"
echo "✅ デプロイが完了しました！"
echo "URL: https://$WEB_APP_NAME.azurewebsites.net"
echo "========================================"
