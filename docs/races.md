# 種族の追加方法 (How to add a new race)

新しい種族をゲームに追加するには、以下のデータとコードを更新する必要があります。

## 1. データ定義 (Data definitions)
以下のJSONファイルに新しい種族のエントリを追加します。
- `game/data/races/races.json`: 種族の基本ステータス (`base`)、スキル補正 (`skill_bias`)、特性の重み (`trait_weights`)、身長 (`height`) などを設定します。
- `game/data/generation/names.json`: 種族の命名規則（男性名、女性名、家族名）を `sets` に追加します。
- `game/data/generation/appearance.json`: `races` オブジェクトに肌の色 (`skins`) と髪の色 (`hair`) のカラーパレットを追加します（エイリアン的な青色は避けること）。

## 2. 村の設定 (Village generation)
- `game/data/buildings/villages.json`: 新しい種族の村の家 (`v_<race>_home` サイズ 3x3) と集会所 (`v_<race>_hall` サイズ 5x5) の建物を追加します。
- `game/data/villages/races.json`: 村の生成設定（取引スタイルや初期関係性、特産品）を追加します。

## 3. 日本語翻訳 (Japanese localization)
- `game/data/i18n/ja/races.json`: 種族の表示名と説明文。
- `game/data/i18n/ja/buildings.json`: 村の建物の表示名と説明文。

## 4. コードの更新 (Code updates)
プロシージャルな3Dモデル（代替メッシュ）の表示のために、以下のコードを修正します。
- `game/src/visual/units/char_mesh.gd`:
  - `metrics` 関数内で、体格の調整（`body_type` が特別必要な場合）。
  - `_race_features` 関数内で、固有の身体的特徴（耳、角、尾など）。
  - `leg` 関数内で、特殊な足（例: ハーフリングの裸足など）の描画。
- `game/src/visual/world/bld_village.gd`:
  - 新しい建物のスタイル（例: `scrap`, `mushroom`, `burrow` など）が必要な場合は、`STYLES` 定数に追加し、`_home` / `_hall` で描画関数を呼び出します。

## 5. ペイントアートの生成について (Painted art)
上記のプロシージャルな3Dモデルに加えて、ポートレートや2Dスプライトといった「ペイントアート」を生成する必要があります。
これらは `tools/art/make_prompts.py` と `tools/art/process.py` を使用して画像生成モデルで作成されます。
詳細な手順については `docs/art_pipeline.md` を参照してください。

