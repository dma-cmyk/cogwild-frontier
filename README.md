# Cogwild Frontier

手続き生成された永続オープンワールドを、住民・部隊・ロボット・ドローン・飛行船に指示を出しながら開拓していく、
RPG 要素のある自律型 RTS の **Playable Vertical Slice**（Godot 4.7 製）。
自分で部隊を動かしても、指示だけ出して眺めていても世界が進みます。
キャラチップ・肖像・建物・木や岩・地面・アイテムアイコン・タイトル画像は画像生成した絵で、3D の地形の上に置いています（手順は `docs/art_pipeline.md`）。
住民は種族 × 見た目 × 性別ごとに 3 種類（いちばん多い作業着の見た目は 4〜5 種類）の絵があり、入植者には同じ組み合わせの住民の中で一番使われていない絵が割り当てられるので、同じ顔が並びにくくなっています。建物はカメラを回すと裏側の絵に切り替わります。
住民は RimWorld のように吹き出しでしゃべります（仕事の一言、近くの仲間との雑談、戦闘中のかけ声、川を泳ぐ・崖を登るときの一言）。
部隊は小隊単位で動かします。左下の **小隊パネル**（顔・体力・態勢・隊形・隊員の出し入れ・名前）で小隊を選び、右下の **命令バー**（建設・採集・移動・攻撃・技など）で命令します。1 人だけ別に動かしたいときは、その人だけの小隊を作ります。
小隊には態勢（攻勢・均衡・慎重・防衛）と隊形（横列・楔形・散開）があり、役割ごとの技（盾打ち・狙い撃ち・爆破チャージ・野戦手当・鼓舞の号令）は自動でも自分のタイミングでも使えます。側面攻撃、木や岩の遮蔽も戦闘に効きます。
川は泳いで、崖はよじ登って越えられます（遅い）。住民に橋や崖の階段を建てさせると速く通れます。カメラは 90° ずつ 4 方向に回せます。
UI は日本語 / 英語に対応しています。

**ブラウザで遊ぶ（PC・スマホ）: https://dma-cmyk.github.io/cogwild-frontier/**
（最初はタイトル表示に必要な core pack を取得し、追加の種族・look・建物アートはゲーム開始後に別パックをバックグラウンド取得します。追加パックは IndexedDB / PWA キャッシュに保存され、次回はすぐ利用できます。新しい版が公開されていると、タイトル画面で自動的に読み込み直します。読み込みが 20 秒止まったら再読み込みボタンが出ます。スマホは横向き推奨）

![開拓地の昼](docs/screenshots/settlement_day.png)

## 起動

```bash
./run.sh              # 初回は自動でインポートしてから起動
# または
godot --path game
```

必要なもの: Godot 4.7（`godot` コマンド）。レンダラーは Compatibility（OpenGL 3.3 / WebGL 2）で、ブラウザ版と同じ見た目になります（開発機は Intel Iris Xe）。

タイトル → **New frontier** で創設者（名前・種族・役割・見た目・会社名と旗の色・ワールドシード）を決めて開始。
同じシードなら同じ世界になります。**Continue / Load** でセーブから再開。

## 設定

タイトル画面またはゲーム中の Esc メニューの **設定 / Settings** で変更できます。設定は保存されます（ブラウザ版はブラウザ内に保存）。

| 項目 | 内容 |
|---|---|
| 言語 | 日本語 / English（タイトル画面右上の **Language / 言語** からも切り替え可） |
| BGM | 自動（タイトル・昼・夜・戦闘で切り替え）/ シャッフル / なし / 曲を固定（5 曲） |
| 音量 | 全体・音楽・効果音・環境音 |
| 画質 | 自動 / 低 / 中 / 高（自動はスマホで低、それ以外は中。高は MSAA と長い影） |
| UI サイズ | 自動 / 小 / 標準 / 大（自動は画面の大きさと画素密度から、スマホでも文字とボタンが読める大きさに） |
| 吹き出し | すべて / 戦闘のみ / なし |

起動時に固定する場合は環境変数 `COGWILD_LANG=ja|en`、または Godot のユーザー引数 `--lang=ja|en` を使います。

```bash
COGWILD_LANG=ja godot --path game
godot --path game -- --lang=en
```

人物名・地名・会社名など、手続き生成される固有名詞はラテン文字のまま表示されます。日本語表示には同梱した Noto Sans CJK JP のサブセットを使用します。ライセンスは `game/assets/fonts/LICENSE-NotoCJK.txt` を参照してください。


## 操作

| 入力 | 動作 |
|---|---|
| 左クリック / ドラッグ | 選択（ユニット・小隊・建物・拠点）/ 範囲選択。小隊の隊員をクリックするとその小隊が命令の対象になる |
| 右クリック | 命令の対象の小隊へ文脈命令: 地面へ移動 / 敵・敵拠点を攻撃 / 資源を採取（住民）/ 交易所へ交易（飛行船） |
| M F H X P Y U R | Move / Attack / Defend / Explore / Patrol / Escort / Auto / Retreat（命令バーの対象: 表示中の小隊・全小隊） |
| Z C V T N J K O I | 小隊の技（命令バーの技ボタンと同じ。対象が要る技は続けて敵・味方・地面をクリック） |
| B / G | 建設メニュー（川の橋・崖の階段は壁と同じく線で配置）/ 採取ゾーンと仕事の優先度 |
| 1–9, Tab | 小隊を選択（同じキーを 2 回押すとその小隊へカメラを移動） |
| 小隊パネル | タブで小隊を切り替え（**全小隊** で全部に命令）。顔カードをクリックで詳細、✕ で隊から外す、左上のボタンでその人だけの小隊を作る、＋ で隊員を追加。鉛筆ボタンで小隊の名前を変更。態勢 / 隊形 / 撤退の目安 / 技の自動使用 |
| W A S D・矢印・画面端・中ボタンドラッグ | カメラ移動 |
| ホイール | ズーム |
| Q / E | カメラを90°ずつ左右に回転 |
| Space / `[` `]` | 一時停止 / 速度（x1 x2 x4） |
| F5 / F9（ブラウザ版は Ctrl+S / Ctrl+L） | クイックセーブ / クイックロード |
| Esc / F1 | 命令・配置の取り消し（選択は外れない）→ 開いている小窓を閉じる → メニュー（セーブ 3 枠・ロード・設定）/ 操作説明 |

タッチ操作（スマホ・タブレット）:

| 操作 | 動作 |
|---|---|
| タップ | 選択（ユニット・建物・拠点・戦利品）。選択中に地面・敵をタップすると移動・攻撃などの文脈命令 |
| 1 本指ドラッグ / 2 本指ピンチ / 2 本指ねじり | カメラ移動 / ズーム / ねじりが約40°を超えると90°回転 |
| 長押し | 指の下にあるものの詳細 |
| 右上の **範囲選択** | オンの間はドラッグで範囲選択 |
| 右上の **マップ** / **詳細** | ミニマップ / 選択中の詳細パネルを開閉 |
| 命令ボタン（移動・攻撃・巡回など） | 表示中の小隊が対象。次にタップした場所が目標 |
| 小隊パネル（左下） | 普段は顔の並ぶ 1 行。ボタンで広げると態勢・隊形・隊員の出し入れ |
| 建設 | 建物を選び、場所をタップして **決定**（壁はドラッグか両端をタップ） |

縦向きでは横向きを勧める案内が出ます（「このまま続ける」で縦のまま遊べます）。タイトル画面の **全画面** でブラウザの全画面表示に切り替えられます。

## 遊び方の例

1. 最初から Alpha 小隊（創設者・護衛・弓兵・Walker）、住民 5 人、Work Bot、Scout Drone、飛行船がいます。
   住民は最初から伐採・採掘・畑を自分で回しています。
2. **Build**（B）で Windmill を建てると電力がプラスになり、ロボットの消費をまかなえます。House で人口上限が増え、移住者が来ます。
3. 小隊パネルのタブ（または 1–9）で小隊を選び、**Explore**（X）→ 地面をクリック。領域を調べ、遺跡の宝を拾い、強すぎる拠点を避けて、帰還時に報告します。
4. 見つけた盗賊の野営地は右クリック（または拠点パネル）で攻撃。倒すと装備や宝箱を落とします。
   弓兵が多い小隊は **慎重**（距離を取って撃ち、被害を抑える）、守りたい場所があるなら **防衛**、押し切るなら **攻勢** に。技を温存したいときは小隊の **技を自動使用** を切り、命令バーの技ボタンで使います。
   川や崖の向こうの拠点へは泳ぐ・登るで行けますが遅いので、よく通る場所には **川の橋** や **崖の階段** を建てます。
   キャラクター詳細の **Equipment → Change** で武器庫の品を装備できます。
5. 任せたいときは小隊を **Auto**（U）に。飛行船は詳細パネルの **Trade run / Auto** で交易所へ余剰を売りに行きます。
6. 発見した種族の村を選ぶと、名前・種族・人口・関係 tier・特産品・依頼が表示されます。村に部隊を立たせて **Trade**（Neutral 以上）し、資源や特産品を売買できます。**Gift** は関係を上げますが、同じ村への連続した贈り物ほど効果が薄くなります。依頼を期限までに **Deliver** すると報酬と関係改善を得られます。
   非敵対村への **Attack** は確認が必要です。守備隊を倒して村を subdued にすると備蓄と戦利品 cache を略奪できますが、村は復興まで ruins になり敵対します。敵対村は **Make peace** の貢納で和平できます。

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
  src/ui/        HUD（命令バー）・情報パネル・小隊パネル・隊員選び（SquadPicker）・ミニマップ・建設メニュー・ポーズメニュー・タイトル
  tests/         ヘッドレステスト（test_*.gd）・ギャラリー・probe シナリオ
  tools/         world_map_dump（生成した世界を PNG に）
tools/art/       make_prompts.py（画像生成のプロンプト）・process.py（生成画像 → ゲーム用素材）・overrides.json
tools/audio/     compose_bgm.py（BGM 5 曲の手続き作曲 → OGG）
tools/web/       fetch_templates.py（Web 書き出しテンプレートの取得）・apply_import_presets.py（テクスチャ圧縮設定）・build_web.sh
.github/         workflows/pages.yml（main への push で Web 版を書き出して GitHub Pages に公開）
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
export COGWILD_LANG=en   # probe のクリック座標は英語 UI が前提
COGWILD_WORLD_SEED=7  python3 $P game --scenario game/tests/probe/explore_day.json    --godot-arg=--time-scale --godot-arg=4
COGWILD_WORLD_SEED=11 python3 $P game --scenario game/tests/probe/combat_camp.json    --godot-arg=--time-scale --godot-arg=4
python3 $P game --scenario game/tests/probe/build_windmill.json --godot-arg=--time-scale --godot-arg=4   # 世界はシナリオの乱数シードから
COGWILD_WORLD_SEED=7  python3 $P game --scenario game/tests/probe/save_load.json      --godot-arg=--time-scale --godot-arg=4
COGWILD_WORLD_SEED=7  python3 $P game --scenario game/tests/probe/crossing.json        # 川を泳ぐ・崖を登る・橋と階段の建設
COGWILD_WORLD_SEED=7  python3 $P game --scenario game/tests/probe/camera_rotate.json   # 4 方向の回転・建物の裏側の絵・タッチのねじり
python3 $P game --scenario game/tests/probe/ui_squad_menu.json      # 小隊パネル: 隊員の追加・外す・一人小隊・全小隊・名前変更・Esc
python3 $P game --scenario game/tests/probe/ui_squad_menu_compact.json --resolution 844x390   # スマホ幅の配置
python3 $P game --scenario game/tests/probe/ui_card_click.json      # 顔カードを 1 回クリックで詳細が開いたままになる
COGWILD_WORLD_SEED=11 python3 $P game --scenario game/tests/probe/ui_abilities_manual.json   # 技の手動使用と自動使用の切り替え
COGWILD_WORLD_SEED=7  python3 $P game --scenario game/tests/probe/perf_exploration_spikes.json   # 3 分の探索で時間を測る（x1）
godot --headless --path game res://tools/world_map_dump.tscn -- --seed=123 --radius=6 --out=/tmp/map.png
```

`COGWILD_WORLD_SEED`（またはユーザー引数 `--world-seed=`）で世界を固定します。combat_camp のシナリオはシード 11 の地形（近くの野営地の位置）に合わせて書いてあります。

```bash
tools/web/build_web.sh                                        # テンプレート取得 → インポート → core + optional pack を build/web に書き出す
python3 -m http.server -d build/web 8072 --bind 127.0.0.1    # http://127.0.0.1:8072/ を開く
```

スレッドなしの Web テンプレート（COOP/COEP ヘッダ不要）を使います。地形・木や岩などの絵は Basis Universal で 1 種類だけ配布し、読み込み時に GPU 形式（PC は BC 系、スマホは ASTC / ETC2）へ変換します。キャラチップと肖像は WebP で、ミップマップを作らず GPU メモリを節約します。追加アートは versioned PCK として分離し、開始後に取得して更新時に自動的に差し替えます。

## 任意の AI 文章生成

ゲームは API なしで完結します。OpenAI 互換のエンドポイントを設定したときだけ、人物の一言・経歴と珍しい品のフレーバー文を
バックグラウンドで書き換えます（数値や挙動は変わりません）。キーはコードに置かず、環境変数で渡します。

```bash
COGWILD_AI_ENDPOINT=https://api.openai.com/v1/chat/completions COGWILD_AI_KEY=... COGWILD_AI_MODEL=... ./run.sh
```

## クレジット

- 人物・機械・建物・木や岩・地面・アイテムアイコン・タイトル画像は、画像生成モデル（OpenAI gpt-image-1、OMP の画像生成ツール経由）で作った絵を `tools/art/process.py` で加工したもの。プロンプトは `art_src/prompts.json`。
- 絵がないものの代替表示・UI アイコン・エフェクトはコードで手続き生成。
- 効果音・環境音は `audio_gen.py`、BGM 5 曲は `tools/audio/compose_bgm.py` による手続き生成（第三者素材なし、OGG Vorbis）。
- フォント: Noto Sans / Noto Serif（`game/assets/fonts/LICENSE-Noto.txt`）、日本語は Noto Sans CJK JP のサブセット（`CogwildCJK-*.otf`、`LICENSE-NotoCJK.txt`、いずれも SIL OFL 1.1）。
