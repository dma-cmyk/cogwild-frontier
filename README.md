# Cogwild Frontier

手続き生成された永続オープンワールドを、住民・部隊・ロボット・ドローン・飛行船に指示を出しながら開拓していく、
RPG 要素のある自律型 RTS の **Playable Vertical Slice**（Godot 4.7 製）。
自分で部隊を動かしても、指示だけ出して眺めていても世界が進みます。
キャラチップ・肖像・建物・木や岩・地面・アイテムアイコン・タイトル画像は画像生成した絵で、3D の地形の上に置いています（手順は `docs/art_pipeline.md`）。
UI は日本語 / 英語に対応しています。

![開拓地の昼](docs/screenshots/settlement_day.png)

## 起動

```bash
./run.sh              # 初回は自動でインポートしてから起動
# または
godot --path game
```

必要なもの: Godot 4.7（`godot` コマンド）。Vulkan 対応 GPU（開発機は Intel Iris Xe）。

タイトル → **New frontier** で創設者（名前・種族・役割・見た目・会社名と旗の色・ワールドシード）を決めて開始。
同じシードなら同じ世界になります。**Continue / Load** でセーブから再開。

## 言語設定

タイトル画面右上の **Language / 言語**、またはゲーム中の Esc メニューから **日本語** / **English** を切り替えられます。変更は保存され、表示中の画面にも反映されます。

起動時に固定する場合は環境変数 `COGWILD_LANG=ja|en`、または Godot のユーザー引数 `--lang=ja|en` を使います。

```bash
COGWILD_LANG=ja godot --path game
godot --path game -- --lang=en
```

人物名・地名・会社名など、手続き生成される固有名詞はラテン文字のまま表示されます。日本語表示には同梱した Noto Sans CJK JP のサブセットを使用します。ライセンスは `game/assets/fonts/LICENSE-NotoCJK.txt` を参照してください。


## 操作

| 入力 | 動作 |
|---|---|
| 左クリック / ドラッグ | 選択（ユニット・小隊・建物・拠点）/ 範囲選択 |
| 右クリック | 文脈命令: 地面へ移動 / 敵・敵拠点を攻撃 / 資源を採取（住民）/ 交易所へ交易（飛行船） |
| M F H X P Y U R | Move / Attack / Defend / Explore / Patrol / Escort / Auto / Retreat（小隊・選択ユニット） |
| B / G | 建設メニュー / 採取ゾーンと仕事の優先度 |
| 1–4, Tab | 小隊を選択 |
| W A S D・矢印・画面端・中ボタンドラッグ | カメラ移動 |
| ホイール / Q E | ズーム / 90° 回転 |
| Space / `[` `]` | 一時停止 / 速度（x1 x2 x4） |
| F5 / F9 | クイックセーブ / クイックロード |
| Esc / F1 | キャンセル・メニュー（セーブ 3 枠・ロード）/ 操作説明 |

## 遊び方の例

1. 最初から Alpha 小隊（創設者・護衛・弓兵・Walker）、住民 5 人、Work Bot、Scout Drone、飛行船がいます。
   住民は最初から伐採・採掘・畑を自分で回しています。
2. **Build**（B）で Windmill を建てると電力がプラスになり、ロボットの消費をまかなえます。House で人口上限が増え、移住者が来ます。
3. 小隊を選んで **Explore**（X）→ 地面をクリック。領域を調べ、遺跡の宝を拾い、強すぎる拠点を避けて、帰還時に報告します。
4. 見つけた盗賊の野営地は右クリック（または拠点パネル）で攻撃。倒すと装備や宝箱を落とします。
   キャラクター詳細の **Equipment → Change** で武器庫の品を装備できます。
5. 任せたいときは小隊を **Auto**（U）に。飛行船は詳細パネルの **Trade run / Auto** で交易所へ余剰を売りに行きます。

## 開発

```text
game/
  data/          JSON のゲームデータ（種族・役割・特性・技能・アイテム・ユニット・建物・生成規則）
  src/core/      DB（データ）・App（入力と画面遷移）・Sfx（音）・RngUtil・Caches
  src/world/     WorldGen（決定的なチャンク生成）・ChunkData・Tiles
  src/sim/       World（10 Hz tick）・ColonyAI・SquadAI・Combat・FactionAI・Economy・SaveGame・NewGame
  src/gen/       NpcGen・ItemGen・NameGen・NamedEnemyGen
  src/visual/    SpriteLibrary（画像生成の絵の検索）・SpriteUnitVisual・MeshKit（低ポリの代替表示）・LookDev・建物/小物/アイコン/VFX・シェーダー
  src/view/      Game（ループ・選択）・WorldView・ChunkView・UnitView・CameraRig・InputController
  src/ui/        HUD・情報パネル・小隊パネル・ミニマップ・建設メニュー・ポーズメニュー・タイトル
  tests/         ヘッドレステスト（test_*.gd）・ギャラリー・probe シナリオ
  tools/         world_map_dump（生成した世界を PNG に）
tools/art/       make_prompts.py（画像生成のプロンプト）・process.py（生成画像 → ゲーム用素材）・overrides.json
art_src/         prompts.json（生成リクエスト一覧）。raw/ は生成結果の原本（大きいので Git 管理外）
docs/            design.md（設計・仮定）、art_pipeline.md（画像生成アート）、contracts.md（モジュール境界）、screenshots/、samples/
```

テスト:

```bash
godot --headless --path game --import
godot --headless --path game res://tests/run_tests.tscn                          # 全部（長時間テスト含む）
godot --headless --path game res://tests/run_tests.tscn -- --filter=sim          # 一部だけ
```

実際に動かしての確認（ウィンドウあり、`~/.omp/agent/skills/game-production/scripts/godot_probe.py`）:

```bash
P=~/.omp/agent/skills/game-production/scripts/godot_probe.py
python3 $P game --scenario game/tests/probe/explore_day.json --godot-arg=--time-scale --godot-arg=4
python3 $P game --scenario game/tests/probe/combat_camp.json --godot-arg=--time-scale --godot-arg=4
python3 $P game --scenario game/tests/probe/build_windmill.json --godot-arg=--time-scale --godot-arg=4
python3 $P game --scenario game/tests/probe/save_load.json --godot-arg=--time-scale --godot-arg=4
godot --headless --path game res://tools/world_map_dump.tscn -- --seed=123 --radius=6 --out=/tmp/map.png
```

probe のクリック座標は英語 UI を前提としているため、全シナリオの実行時は `COGWILD_LANG=en` を指定してください。

## 任意の AI 文章生成

ゲームは API なしで完結します。OpenAI 互換のエンドポイントを設定したときだけ、人物の一言・経歴と珍しい品のフレーバー文を
バックグラウンドで書き換えます（数値や挙動は変わりません）。キーはコードに置かず、環境変数で渡します。

```bash
COGWILD_AI_ENDPOINT=https://api.openai.com/v1/chat/completions COGWILD_AI_KEY=... COGWILD_AI_MODEL=... ./run.sh
```

## クレジット

- 人物・機械・建物・木や岩・地面・アイテムアイコン・タイトル画像は、画像生成モデル（OpenAI gpt-image-1、OMP の画像生成ツール経由）で作った絵を `tools/art/process.py` で加工したもの。プロンプトは `art_src/prompts.json`。
- 絵がないものの代替表示・UI アイコン・エフェクトはコードで手続き生成。
- 効果音・BGM・環境音は `audio_gen.py` による手続き生成（第三者素材なし）。
- フォント: Noto Sans / Noto Serif（`game/assets/fonts/LICENSE-Noto.txt`）、日本語は Noto Sans CJK JP のサブセット（`CogwildCJK-*.otf`、`LICENSE-NotoCJK.txt`、いずれも SIL OFL 1.1）。
