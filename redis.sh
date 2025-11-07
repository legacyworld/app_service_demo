#!/bin/bash

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

echo "=== Azure Cache for Redis 作成 ==="
az redis create \
    --name $REDIS_NAME \
    --resource-group $RESOURCE_GROUP \
    --location $REGION \
    --sku $SKU \
    --vm-size $VM_SIZE

echo "=== Redis のプロビジョニング完了を待機中..."

RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    
    # provisioningState を取得
    # --query provisioningState -o tsv を使用して、状態文字列のみを取得
    STATE=$(az redis show \
        --name $REDIS_NAME \
        --resource-group $RESOURCE_GROUP \
        --query provisioningState \
        -o tsv 2>/dev/null) # エラーメッセージを抑制

    if [ $? -ne 0 ]; then
        echo "エラー: az redis show の実行に失敗しました。リソース名を確認してください。"
        exit 1
    fi

    echo "現在の状態: $STATE (試行回数: $((RETRY_COUNT + 1))/${MAX_RETRIES})"

    if [ "$STATE" == "Succeeded" ]; then
        echo "=== プロビジョニングが完了しました (Succeeded) ==="
        break
    elif [ "$STATE" == "Failed" ]; then
        echo "=== エラー: プロビジョニングが失敗状態になりました ==="
        exit 1
    fi
    
    # 待機
    sleep $SLEEP_TIME
    RETRY_COUNT=$((RETRY_COUNT + 1))
done

# タイムアウトチェック
if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "=== タイムアウト: 指定された時間内に Redis のプロビジョニングが完了しませんでした ==="
    exit 1
fi


echo "=== 作成結果確認 ==="
az redis show --name $REDIS_NAME --resource-group $RESOURCE_GROUP


echo "=== Redis キー取得 ==="
az redis list-keys --name $REDIS_NAME --resource-group $RESOURCE_GROUP

