# 種族の足し方

種族はほぼデータで決まります。ゲーム側のコードに種族の一覧はありません（`AppearanceGen.race_ids()` は `data/races/races.json` の `playable` な行、絵の高さは同じ行の `height`、村の建物の大きさは `data/buildings/villages.json` の `size` から読みます）。

## 1. データ

| ファイル | 足すもの |
|---|---|
| `game/data/races/races.json` | 能力（`base`）、得意な技能（`skill_bias`）、特性の出やすさ（`trait_weights`、既存の特性 id だけ）、年齢、`height`（絵の立ち姿の高さ m）、`spawn_weight`（移住者・町の住民に混ざる割合）、`playable` |
| `game/data/generation/names.json` | `sets.<種族>` に男女・中性の名前と家名 |
| `game/data/generation/appearance.json` | `races.<種族>` の肌と髪の色（青系は避ける。青は会社の色として色相回転される） |
| `game/data/villages/races.json` | 村の性格（`temperament`・`starting_relation`）、好む地形（`biome_preference`）、名産品・欲しいもの・在庫、見張りの数（`guards`）、代わりの建物の形（`build_style`）と色 |
| `game/data/buildings/villages.json` | `v_<種族>_home`（3×3）と `v_<種族>_hall`（5×5） |
| `game/data/i18n/ja/races.json`・`ja/buildings.json` | 日本語の名前と説明 |
| `game/data/villages/dialogue.json` | 村人の台詞（種族ごとの行がなければ共通の行を使う） |

## 2. コード（見た目の代わりのモデルだけ）

- `game/src/visual/units/char_mesh.gd`: `metrics()` の体の高さ・幅の補正、`_race_features()` の耳・角・尾などの形。
- `game/src/visual/world/bld_village.gd`: 既存の `build_style` で合わない村の形なら、形を足す。

描いた絵が届く前や読み込めないときは、このモデルで表示されます。

## 3. 描いた絵

`tools/art/make_prompts.py` に種族の姿（`CLASSIC_RACES` / `CLASSIC_RACES_V2` と `CLASSIC_RACE_BODY` のような表）と村の建物（`VILLAGE_BUILDINGS`）を足し、`tools/art/process.py` の `NEW_RACES` に種族を足します。生成・加工の手順は `docs/art_pipeline.md`。ブラウザ版では `tools/web/pack_split.py` の `LATE_RACES` に足すと、その種族の絵が後から読み込む追加パックに入ります。

## 4. 確認

- `tests/test_painted_art.gd`: すべての種族 × 見た目 × 性別にチップと肖像が 2 種類以上あるか。
- `tests/test_i18n.gd`: 日本語の名前があるか。
- `tests/test_villages.gd`: 村がその種族の好む地形に置かれるか。
- 作成画面のプローブ `tests/probe/ui_creation.json` / `ui_creation_phone.json` で、選択肢が画面に収まるかを見る。
