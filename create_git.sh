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

echo "次に表示されるユーザ名とパスワードを使用して、Gitプッシュを行います。"
az webapp deployment list-publishing-credentials \
    --name "$WEB_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query "{publishingUserName:publishingUserName, publishingPassword:publishingPassword, webappName:name}"
