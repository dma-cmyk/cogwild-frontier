# Cogwild Frontier — Vertical Slice 報告（2026-09-26）

起動: `./run.sh`（または `godot --path game`）。操作・遊び方は README、設計と仮定は `docs/design.md`。

## 実装した機能

- **タイトルとキャラクター作成**: 名前・種族（Human / Sylvan / Stoutkin / Vulpin）・役割（8 種、固定クラスではなく初期能力と装備の出発点）・見た目（ランダム、髪型、髪色、性別）・会社名と旗の色・ワールドシード。3D プレビュー付き。
- **手続き生成の永続世界**: 32 m チャンクを探索した方向へ生成（seed と座標の純関数）。段丘の崖、川（浅瀬・橋）、湖、森、草原、岩場、鉱脈、エーテル結晶、踏み跡の道。開始地点は平坦・水と森の近く・崖の上でない場所を採点で選択。拠点 8 種（遺跡、盗賊の野営地、機械の拠点、交易所、放浪者の野営地、飛行船の残骸、結晶の林、鉱床）を距離に応じた危険度で配置し、開始地点付近には必ず主要な拠点を用意。
- **開拓地**: Hearth（3 段階に拡張）、House、Storehouse、Smelter（鉱石→金属）、Windmill（電力）、Robot Workshop（機械の生産）、Sky Dock、Watchtower（自動射撃）、Stone Wall（ドラッグで列配置）、Outpost（拠点外の建設圏）。配置時に可否と理由を表示、住民が資材を運んで建てる、キャンセルで返金。
- **住民の自律行動**: 伐採・採掘・採集・畑（耕す→植える→育つ→収穫）・運搬・建設・精錬・機械の組立・夜の休息・敵からの避難。優先度（5 系統 × 4 段階）で調整。技能は使うほど上がり（NPC ごとに適性が違う）、レベル・称号・軍の階級が付く。
- **部隊と委任**: Move / Attack（敵・拠点・地点）/ Defend / Explore / Patrol / Escort / Retreat / Auto、撤退閾値スライダー、最大 6 人、住民の徴兵・復帰、新しい小隊の編成。
- **戦闘**: 近接・射撃・投射物・範囲攻撃・会心・装甲、ダウン→回復（負傷）/死亡、戦利品袋（レア以上は光の柱）、名前付きの頭目が固有能力を使う。
- **機械**: Work Bot（住民と同じ仕事、休まない、電力消費）、Walker（二脚の重火力）、Scout Drone（自動偵察）、Repair Drone（回復）、Cargo Airship（探索・交易・自動、飛行で地形を無視）。敵側に Sentry / Turret / War Drone / Machine Warden、商人の飛行船。
- **世界の自律的な動き**: 盗賊の巡回・略奪隊・3 日ごとの拠点拡張（テント増設）・掃討後の再占拠、機械拠点の歩哨再建、商人の飛行船の来訪（余剰の買取と品物の販売）、空き家と食料による移住、放浪者の合流。遠い拠点は休眠して日次処理だけ（簡易シミュレーション）。
- **生成された NPC / アイテム**: 技能 11 種・特性 36 種・癖 85 種・経歴テンプレート、才能の偏り（天才・凡人・戦闘だけ強い等）。アイテム 49 土台 × 素材 × 品質 8 段階 × 接辞 33 種、固有名の異常品。外見 DNA（人物・ロボ・ドローン・飛行船・アイテム）から形と肖像とアイコンを再構築。
- **セーブ/ロード**: 3 枠 + クイック（F5/F9）。seed・地形の変更差分・探索済みマップ・全ユニット（人物記録・DNA・装備・命令・AI 状態）・建物・小隊・拠点状態・戦利品・畑・ゾーン・乱数状態を JSON で保存。版番号と破損ファイルの検出。
- **UI**: 上部の資源バー（増減/分）・人口/住宅・電力・日時・速度、通知（クリックで移動）、ミニマップ（探索範囲・味方/敵/拠点/カメラ枠、クリック移動、右クリック移動命令）、小隊パネル（肖像・クラス・Lv・HP/EN）、コマンドバー、詳細パネル（肖像・装備の付け替え・特性・技能・経歴・記録、建物の生産と拡張、拠点への攻撃/探索指示）、建設メニュー、ゾーンと優先度、交易パネル、名簿、ポーズメニュー、操作説明（F1）。
- **昼夜・速度**: 1 日 4 分（x1）、夜は窓や街灯が灯る。Pause / x1 / x2 / x4。
- **音**: 手続き生成の効果音・BGM・風の環境音（ライセンス不要）。
- **任意の AI 文章生成層**: OpenAI 互換エンドポイントを環境変数で設定したときだけ人物の一言・経歴とアイテムのフレーバー文を書き換える（キーはコードに置かない、未設定なら無効）。

## 今遊べるゲームループ

作成 → 開拓地（最初から住民が働いている）→ 建設とゾーンで生産を伸ばす → 小隊・ドローン・飛行船で探索し拠点を発見 →
盗賊の野営地を掃討して戦利品を装備 → 略奪隊への防衛・商人との交易・移住で人口増 → さらに外へ。
指示を出して x4 で眺めているだけでも、住民の作業・ドローンの偵察・飛行船の交易・略奪・来訪・称号獲得が進みます。

## テスト結果（実行したもの）

| 種類 | コマンド / シナリオ | 結果 |
|---|---|---|
| 全リソース読込 | `godot_probe.py game --health` | PASS（エラー・警告 0） |
| ヘッドレステスト | `godot --headless --path game res://tests/run_tests.tscn` | 23/23 PASS（77 s） |
| 決定性 | 同 seed で 900 tick 後の全状態が一致 | PASS |
| セーブ/ロード | 保存→読込で全状態一致、さらに 600 tick 進めても一致（float は 1e-6 で比較） | PASS |
| 長時間 | 10 日間放置（小隊 Auto・飛行船 Auto） | PASS: 負の資源・NaN なし、ユニット 94 以下、探索約 15 万タイル、拠点約 25 発見、約 2 ms/tick |
| 生成 | 品質分布 2 万回、NPC 才能の偏り 500 人、名前の重複、データ相互参照 | PASS |
| 見た目 | 全建物 × 全様式 × 段階、全小物の予算、全アイコンが互いに異なる、全 VFX | PASS |
| AI 層 | 未設定で無効 / ローカルのモックサーバーで実際に HTTP 往復し文章だけ書き換わる | PASS |
| 実プレイ（ウィンドウ） | `tests/probe/explore_day.json`（探索と報告）、`combat_camp.json`（seed 11 で野営地を掃討・戦利品 8 個）、`build_windmill.json`（UI クリックで配置→住民が建設）、`save_load.json`（F5→F9 で続行）、タイトル→作成→開始 | すべて PASS |

## パフォーマンス（Intel Iris Xe、1600×900、Mobile レンダラー、vsync なし）

| 場面 | 平均 | p95 | draw calls | primitives |
|---|---|---|---|---|
| x1・既定ズーム | 11.0 ms | 13.5 ms | 512 | 65 万 |
| x1・最大ズームアウト | 15.7 ms | 18.2 ms | 739 | 109 万 |
| x4・既定ズーム | 12.4 ms | 23.4 ms | 525 | 66 万 |

注意: チャンク生成（1 個約 15 ms）と初回のシェーダーコンパイルで 250 ms 前後の単発のカクつきが出る。
大量の木は MultiMesh、草花は地形メッシュに結合、カメラから遠いチャンクは非表示、影距離 100 m。

## 何が面白く、何が弱いか（実際に動かした所感）

面白い:
- 1 クリックの指示が「運ぶ→建てる→完成通知」まで勝手に進み、窓が灯る夜の村を眺めているだけで楽しい。
- 住民の称号（Timberwolf、Deepdelver など）やレベルアップ、頭目の「Volley!」、仲間の「ダウン→負傷して起き上がる」が通知で小さな物語になる。
- 霧の中に探索済みの島が広がっていく絵（ズームアウト時）が開拓感を強く出している。
- 生成された名前・特性・癖・装備の組み合わせに毎回違いがあり、ゴミの中にたまに良品が混じる。

弱い:
- ドローンと飛行船の自動偵察が速すぎて、小隊の探索が「もう地図化済み」で終わりやすい（発見の楽しみを機械に取られる）。
- 戦闘が小さく速く、既定ズームでは誰が誰と戦っているか読みにくい（ダメージ表示・狙いの線がない）。最初の野営地戦は五分五分で、撤退→再挑戦を理解していないと負けに見える。
- 3〜4 日目以降、食料と金が余りがちで、選ぶべきこと（使い道・制約）が少なく、家を建てないと成長が止まる。
- 一部の拠点は川や崖で届かない（小隊は「道が見つからない」と通知して待機する）。
- 飛行船は既定カメラからは気球がほとんどで、ゴンドラが見えにくい。

## 今後足しやすいもの（仕組みはあるもの）

データ追加だけで増やせる: 種族・役割・特性・技能・アイテム土台/素材/品質/接辞・ユニット・建物コスト・名前/癖/経歴・固有能力・地名・世界生成の規則。
コードの差し込み口: 隊形とスタンス（`Squad.formation/stance`、`SquadAI._slot()/_engage()`）、固有敵の生成（`NamedEnemyGen`）、
建物の見た目（`BuildingVisuals`）、生産レシピ（`buildings.json` の `recipe`）、AI 文章生成（`AiEnrichment`）。

## 既知の問題

- 届かない拠点がある（上記）。開始地点付近の必須拠点は高さを揃えて配置し、川の浅瀬を増やして減らしている。
- ユニット同士の押し合い（回避）はない。重なることがある。
- セーブ/ロード後の継続は float の末尾誤差を除いて一致（完全なビット一致ではない）。
- UI は英語のみ。
- 世界の広さは開始点から ±320 m（設定値）。
- タイトル画面は背景が単色のグラデーション。

## 変更ファイル（新規プロジェクト。主要なもの）

- `README.md`, `run.sh`, `.gitignore`, `docs/design.md`（設計・仮定・参考画像の分析）, `docs/contracts.md`（モジュール境界）, `docs/samples/`（生成サンプル）, `docs/screenshots/`
- `game/project.godot`, `game/scenes/main.tscn`, `game/scenes/game.tscn`
- `game/src/core/`（db, app, sfx, rng_util, caches）
- `game/src/world/`（world_gen, chunk_data, tiles）
- `game/src/sim/`（world, unit, building, squad, colony_ai, squad_ai, combat, faction_ai, economy, character_factory, new_game, save_game）
- `game/src/gen/`（npc_gen, item_gen, name_gen, named_enemy_gen, gen_util, ai_enrichment）
- `game/src/visual/`（mesh_kit, look_dev, appearance_gen, unit_visual(_factory), portrait_renderer, building_visual(s), prop_meshes, vfx, icons, units/*, world/*, shaders/*）
- `game/src/view/`（game, world_view, chunk_view, unit_view, camera_rig, input_controller）
- `game/src/ui/`（hud, ui_theme, info_panel, squad_panel, minimap, build_menu, pause_menu, roster_panel, title_screen）
- `game/data/`（races, roles, traits, skills, items, units, robots, airships, buildings, factions, generation）
- `game/assets/`（icons 84 SVG, audio 34 効果音 + BGM + 環境音, fonts Noto）
- `game/tests/`（テスト 6 ファイル + 基底 test_case.gd、run_tests、ギャラリー 4 種、probe シナリオ 7 種、モック AI サーバー）, `game/tools/world_map_dump`

Git: 新規リポジトリに初回コミット `e87e29b`（以降の修正は追加コミット）。

## スクリーンショット

`docs/screenshots/`: `title.png`, `character_creation.png`, `settlement_day.png`, `night.png`, `trader_docked.png`,
`exploration_report.png`, `bandit_camp.png`, `combat_retreat.png`, `build_menu.png`, `windmill_built_via_ui.png`,
`world_overview_zoomed_out.png`, `machines.png`, `icons.png`, `world_map_seed11.png`、制作中の確認用は `docs/screenshots/dev/`。
