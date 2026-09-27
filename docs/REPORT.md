# Cogwild Frontier — Vertical Slice 報告（2026-09-26）

起動: `./run.sh`（または `godot --path game`）。操作・遊び方は README、設計と仮定は `docs/design.md`。

## 更新（2026-09-27 その 3）: 前回の弱点の修正（カメラ・顔の重複・戦術・川と崖・カクつき・読み込み）

- **カメラの回転**:
  - Q / E、ミニマップ上端の回転ボタン、タッチの 2 本指ねじり（約 40°）で、90° ずつ 4 方向に回せます。
  - 建物の絵は 1 方向しかないので、基準と 180° では絵のまま、±90° では左右反転して出します（矩形の敷地なら輪郭が一致する、等角ゲームの定番の方法）。反転しても奥行きの書き込みは正しく、建物の裏のユニットは隠れます。
  - 夜の窓の光、会社の色、建設中の足場、風車の羽根も反転に合わせました。移動・範囲選択・建設の配置・壁の線は、どの向きでも画面基準で動きます。ミニマップは北が上のままで、視野の枠が向きを示します。
- **同じ顔の重複**:
  - 人物のチップと肖像をもう 1 組（v3。チップ 40 種・肖像 40 枚）画像生成しました。v2 は種族ごとに同じ髪型・髪色でしたが、v3 は種族 × 見た目ごとに年齢・髪・ひげ・そばかす・眼鏡・帽子を変えています。
  - 人物の絵は 84 種から 124 種になりました。
  - 入植者・移住者・勧誘した人には、同じ種族・見た目・性別の住民の中で一番使われていない絵を割り当てます（乱数は使わない）。同じ組み合わせの人が 3 人までなら顔が重なりません。古いセーブの住民は元の絵のままです。
  - 会社一覧（ロスター）の行に肖像を付けたので、顔の違いが一覧で分かります。
- **戦闘の駆け引き**:
  - 小隊パネルで **態勢**（攻勢 / 均衡 / 慎重 / 防衛）と **隊形**（横列 / 楔形 / 散開）を選べます。近接は前列、射手・支援は後列に入り、同じ敵を囲むときは別々の角度から攻めます（重なりが減りました）。
  - 役割の技が自動で出ます: 盾打ち（気絶）、狙い撃ち（溜め・被弾で中断）、爆破チャージ（範囲）、野戦手当（回復・ダウンからの復帰を早める）、鼓舞の号令（周囲を強化）。敵の盗賊・機械・固有敵も同じ規則で使います。
  - 側面攻撃（命中とダメージが上がる）と、木や岩の遮蔽（射撃が当たりにくい）が効き、浮き文字と吹き出しで分かります。
  - 同じ戦闘を決定論的に比べた結果: 均衡・横列は被ダメージ 116・18.9 秒、慎重・楔形は被ダメージ 183・19.9 秒（どちらも死者なし）。選択で結果が変わります。
- **川と崖を越える**（ユーザーの提案）:
  - 人と軽い二脚の機械は、川を泳いで（遅い、腰まで水に沈んで見える）、崖をよじ登って（遅い）越えられます。車輪・履帯・重い機械は越えられません。自然の湖は泳げません。
  - 建設メニューに **川の橋**（木材 12・石 2 / 区間）と **崖の階段**（木材 8・石 6 / 区間）を追加しました。壁と同じく線で配置し、住民が建てます。探索済みなら開拓地から遠くても置けます。完成すると道と同じ速さで通れます。
  - 経路は遅い泳ぎ・登りを避け、橋・浅瀬・道を優先します。
  - 以前に野営地へ歩いて行けなかったシード（3・21・42）でも、攻撃命令で野営地に着いて戦います（シード 3・7・11・21・42 をテストで確認）。
  - 泳ぐ・登る・橋や階段を建てるときの吹き出しも追加しました（例:「ここに橋があれば泳がずに済むのに。」）。
- **カクつき**:
  - 一番大きな単発のカクつきの原因は、盗賊の野営地などの拠点が見つかった瞬間に、その建物の見た目（最大 40 棟）を 1 フレームでまとめて作っていたことでした（計測で 402 ms）。今は 1 フレーム 1 棟ずつ作ります（拠点の状態と敵は即座に存在します）。
  - ミニマップの描き足しも 1 フレーム 1 チャンクに分け、開始時の周辺チャンクの無駄な作り直しをなくしました。
- **ブラウザ版の読み込み**:
  - `index.pck` を 52.3 MB から 39.1 MB に減らしました（v3 の絵 80 枚を足したうえで）。転送量は約 61 MB から約 48 MB です（wasm は圧縮で約 10 MB）。
  - 内訳: 日本語の太字フォントを外して通常体から太字を合成、肖像を WebP（品質 0.9）、キャラチップを WebP（品質 0.85）、窓の光のマスクを 512 px までに、タイトル画像を WebP にしました。最も寄ったズームで見比べて、劣化は見えませんでした。
  - 読み込み画面は、読み込んだ MB 数を表示し、20 秒進まなければ日英のメッセージと「再読み込み」ボタンを出します。
  - 2 回目以降はサービスワーカーのキャッシュから読み込みます。書き出しごとにキャッシュ名が変わるので、更新後に古い版が残ることはありません（COOP/COEP は不要のまま）。
- **その他**:
  - 回転ボタンの矢印（↶ ↷）がブラウザ版では日本語フォントに無く、四角（豆腐）で表示されていました。SVG のアイコンに替えました。
  - テスト実行の最初に出ていた `add_child() failed`（親ノードが準備中）のエラーを直しました（テストの開始を 1 フレーム遅らせる）。
  - 建設メニューの項目が増えて位置がずれたので、`build_windmill` シナリオのクリック位置を直しました。
- **性能**（Iris Xe・1600×900・画質「中」・x1、各 2 回）:
  - 開拓地（showcase）: 平均 10.0〜10.5 ms、p95 12.9〜13.6 ms（前回 p95 25.4 ms、同じシナリオを変更前の版で測ると 18.7 ms）。
  - 3 分間の探索（新しいチャンクへ進み続ける）: 平均 9.8 ms、p95 13.0 ms、最悪 154 ms（前回は約 0.5 秒の単発あり）。
  - VRAM: 107〜125 MB（前回 86 MB）。WebP にした絵は GPU 上では非圧縮になるためです。

面白い点・弱い点（今回の変更後）:

- 戦闘前に「弓兵が多いから慎重に」「この丘を守るから防衛」と選ぶ理由ができ、盾打ちや狙い撃ちの通知と「側面を取ったぞ！」の吹き出しで、戦いの流れが追えるようになりました。
- 川や崖が「越えられない壁」から「遅い近道」に変わり、よく通る場所に橋や階段を架けるという、建設の新しい目的ができました。
- カメラを回すと、建物の裏に隠れた住民を探せ、開拓地が立体的に見えます。ただし ±90° の建物は左右反転なので、扉や看板の位置が変わります。
- 顔の重複は 12 人の開拓地で目立たなくなりました。同じ組み合わせの人が 4 人以上になると、また重なります。
- 戦術はまだ自動の比重が大きく、技を自分のタイミングで使うことはできません。態勢の違いは被ダメージや撤退の早さに出ますが、画面上の差は小さめです。
- 崖の階段の見た目は「崖に板を並べた」程度で、橋ほどは分かりやすくありません。橋に向けて移動を命じると、橋の横の浅瀬で止まることがあります。
- 最悪フレームは 154 ms まで下がりましたが、0 にはなっていません（拠点の見た目の作成は 1 棟 5〜13 ms）。ブラウザ版のフレーム時間は今回は測っていません。
- スマホは今回もデスクトップ Chrome の端末エミュレーションでの確認です（2 本指ねじりの回転、態勢の変更まで確認）。エミュレーションでは作成画面のスワイプでのスクロールが効かず（前回の公開版でも同じ）、ホイールで確認しました。実機のタッチでスクロールできるかは未確認です。

## 更新（2026-09-27 その 2）: 音と設定・スマホとブラウザ・住民の見た目・戦闘・吹き出し

**ブラウザで遊ぶ: https://dma-cmyk.github.io/cogwild-frontier/**（`main` への push で GitHub Actions が Web 版を書き出して公開）

- **音を軽く、選べるように**:
  - 効果音 37 個を WAV から OGG Vorbis にしました（WAV は削除）。
  - BGM は `tools/audio/compose_bgm.py` で 5 曲（タイトル・昼の開拓地・工房・夜・戦闘）を手続き作曲しました。ループ継ぎ目と音量（-20〜-14 LUFS）を測定済みで、音声は合計 1.9 MB です。
  - Music / SFX / Ambience のバスとリミッターを入れました。
- **設定画面**（タイトルの「設定」と Esc メニュー）: 言語、BGM（自動＝場面で切り替え / シャッフル / なし / 曲を固定）、音量 4 系統、画質（自動 / 低 / 中 / 高）、UI サイズ、吹き出しを変えられます。`user://settings.cfg`（ブラウザ版は IndexedDB）に保存されます。
- **作成画面の空ボタン**: 名前の隣のボタンはアイコンの SVG が無く、何も描かれていませんでした。サイコロのアイコンと「ランダム / おまかせ」の文字を付けました。
- **スマホ対応**:
  - タッチ操作: タップで選択と命令、1 本指でカメラ移動、ピンチでズーム、長押しで詳細、範囲選択の切り替え、建設は「決定 / 取消」、壁は両端をタップ。
  - 画面の大きさ: 画面の大きさと画素密度から UI を自動で拡大し、横幅の狭い画面ではミニマップと詳細パネルを引き出し式にします。
  - その他: 縦向きでは横向きを勧める案内、全画面ボタン、仮想キーボード。タッチ端末では画面端スクロールを切りました。
- **ブラウザ版**:
  - Compatibility レンダラー（WebGL 2）に統一し、デスクトップ版も同じ見た目になりました。
  - 絵は Basis Universal で 1 種類だけ配布し、読み込み時に GPU の形式へ変換します。
  - 画質のプリセットを用意しました（低は草木の密度・影・細部を落とす）。
  - チャンクの見た目の生成を 1 フレーム 3.5 ms までに分割し、開始地点周辺だけは開始時にまとめて作ります。
  - スレッドなしのテンプレートなので、COOP/COEP ヘッダの無い GitHub Pages でも動きます。読み込みは約 92 MB です。
- **住民の見た目の種類**:
  - 人物のチップと肖像をもう 1 組ずつ画像生成しました（v2。チップ 40 種・肖像 40 枚。v1 を画風の参照画像にして、髪型・髪色・服・小物を変えています）。
  - 人物の絵は 44 種から 84 種になりました。住民は DNA から v1 か v2 が決まり、創設者は作成画面の「見た目 1/2」で選べます。
  - シミュレーション用の乱数は消費しないので、同じシードなら以前と同じ世界です。
- **戦闘の手応え**:
  - ダメージと「はずれ」の数字が浮かぶようにしました。
  - 近接は斬撃の弧、被弾はフラッシュとのけぞり、ダウンは倒れる動きで見せます。画面内の近くで爆発が起きると画面が揺れます。
  - エフェクトは画質「低」で量を減らします。
- **建物とカメラの角度**: カメラの見下ろし角を 38° から 30° にし、画像生成した建物の 2:1 の等角と揃えました。建物の絵は 1 方向だけなので、カメラの回転（Q/E）はなくしました。
- **吹き出し（RimWorld 風）**:
  - 住民が話す内容は 3 種類です。
    - 仕事中の一言: 伐採・採掘・運搬・建設・畑・巡回・探索など。
    - 近くの仲間との雑談: 2 人の掛け合い。
    - 戦闘中のかけ声: 被弾・助けを呼ぶ・撤退・敵を倒した・持ちこたえた、など。
  - 日本語と英語でそれぞれ 64 行あります。
  - 表示の制限: 人物ごとにクールダウンがあり、画面上は最大 5 個です。重なる吹き出しはずらし、詳細パネルの上には出しません。
  - 設定で「すべて / 戦闘のみ / なし」を選べます。
- **小隊の攻撃経路**: 攻撃目標までの道が「まだ生成されていない土地」を通る場合、以前はすぐ「道が見つからない」と諦めていました。今は間の土地を生成してから探し直します。
- **テスト**: `test_chatter.gd`（吹き出しの日英対応・話者の条件）を追加しました。v2 の網羅と選択は `test_painted_art.gd` に、翻訳の抜けの検査は全カタログを対象にしました。全 38 件 PASS です。
- **性能**（Iris Xe・1600×900・Compatibility・画質「中」）:
  - x1・既定ズーム: 平均 14.6 ms（前回 12.7〜14.4 ms）、p95 25.4 ms（前回 16〜19 ms）。
  - VRAM: 86 MB（前回 215 MB）。
  - ブラウザ版（Chrome・同じ PC）: ローカル版はゲーム中 約 45 fps、タイトル 96 fps。公開版を開いた計測では約 29 fps（p95 83 ms）でした。この計測時は PC のメモリが逼迫しており、スワップを 8.9 GB 使っていました。

面白い点・弱い点（今回の変更後）:

- 住民が「いい木だ。全部使おう。」「だんだん形になってきた。」とつぶやき、戦闘では「下がって立て直そう！」「やられた…まだ立てる！」と叫びます。眺めているだけで、誰が何をしているかが分かるようになりました。放置プレイの楽しさが一番上がった変更です。
- 数字と斬撃が出るので、誰が誰を殴っているかが読めるようになりました。ただし戦闘そのもの（隊形・スキルの駆け引き）はまだ浅いです。
- 建物の角度が絵と合い、村の見た目が安定しました。代わりにカメラを回せなくなりました。
- 人物の絵は 2 倍になりましたが、同じ種族・装備・性別の住民は 2 種類の絵のどちらかなので、10 人を超えると同じ顔がまた目立ちます。
- スマホはデスクトップ Chrome の端末エミュレーション（iPhone 12 の横向き）で、タイトル → 設定 → 作成 → 開始 → 選択・移動・ピンチ・建設まで確認しました。実機では確認していません。ボタンが多く、小さい画面ではまだ窮屈です。
- 近い盗賊の野営地が川や崖の向こうで歩いて行けない世界がまだあります。試したシード 5 個中 3 個が該当しました（小隊は通知して待機します）。
- Compatibility レンダラーにしたので、ネイティブ版の p95 が前回より悪化しています。チャンク生成の単発のカクつき（約 0.5 秒）も残っています。


## 更新（2026-09-27）: 日本語対応と画像生成アート

- **日本語 / 英語の切り替え**:
  - 切り替え場所: タイトル画面右上の「Language / 言語」と、ゲーム中の Esc メニュー。
  - 切り替えは即時に反映され、`user://settings.cfg` に保存されます。起動時に固定するなら `COGWILD_LANG=ja|en` または `--lang=`。
  - 翻訳対象: UI 全体、通知（シミュレーション側は key と引数で保存するので、切り替えると過去の通知も訳し直されます）、データ表（種族・役割・特性・技能・アイテムの土台/素材/品質/接辞・建物・機械）、生成文（癖・一言・経歴・アイテムの説明文・頭目の異名）、アイテム名の日本語での組み立て。
  - 英語: 表示は以前と一字一句同じです。人名・地名・会社名などの固有名詞は生成されたラテン文字のままです。
  - フォント: Noto Sans CJK JP のサブセットを同梱しました。
- **画像生成アート**（`docs/art_pipeline.md`）: 約 100 枚を生成し、`tools/art/process.py` で背景除去・切り出し・正規化してゲームに組み込みました。3D の地形・影・昼夜・カメラ回転はそのままで、絵をカメラ正対の板として置いています。
  - **キャラチップ**: 4 種族 × 5 種類の見た目 × 男女 = 40 種に、盗賊 4 種を加えました。4 方向 × 3 コマの歩行で、攻撃・被弾・作業・ダウンはカードの動きで表現します。武器の持ち替えで見た目の種類が変わり、会社の色は絵の青だけを色相回転して反映します。
  - **機械**: Work Bot・Walker・両ドローン・Sentry・Turret・War Drone・Machine Warden と、飛行船 2 種です。
  - **肖像**: チップを入力画像にして同じ人物のバストアップを描かせました（44 枚）。
  - **建物**: 全 30 種と集会所の 3 段階・家の差分・建設中の足場・壁です。各画素に奥行きがあるので、ユニットが建物の前後を正しく通ります。夜は窓の灯りが光り、風車の羽根は回り、煙突の位置から煙が出ます。
  - **自然**: 木（針葉樹 12 種など）・岩・鉱石・結晶・茂み・切り株・葦・草花を風で揺らしています。地面は 8 種類のテクスチャを手描き風の境界で混ぜています。
  - **その他**: アイテムと資源のアイコン 60 種、タイトル画面のキーアートです。
- **テスト**: 画像アートの網羅（`test_painted_art.gd`）と翻訳の網羅（`test_i18n.gd`）を追加しました。全 34 件 PASS です。
- **性能**（Iris Xe・1600×900）: 画像アートでは板の数は減りましたが、テクスチャの読み込みと重ね描きが増えました。
  - 既定の拡大率では平均 14.4 ms（従来 11.0 ms）です。
  - 最も引いた状態では 15.7 ms（ほぼ同じ）です。
  - VRAM は約 215 MB です（テクスチャは BC7 圧縮）。

面白い点・弱い点（見た目の変更後）:

- 参考画像の「描き込まれた村」にかなり近づきました。窓が灯る夜、揺れる森、旗の立つ盗賊の野営地が、一目で何の場所か分かるようになりました。肖像も個性が出て、小隊パネルが楽しくなりました。
- 人物は「種族 × 見た目 × 性別」の 44 種で表すので、同じ種類の住民は同じ絵になります（DNA の髪型・髪色の違いは絵に出ません）。
- 生成画像の等角の角度（約 30°）とゲームのカメラ（38°）が少し違うため、建物がわずかに浅い角度に見えます。カメラを 90° 回すと、建物は同じ絵のまま（裏側を描いていない）です。
- 攻撃・被弾は板の動きだけなので、戦闘の迫力はまだ弱いです。

## 実装した機能

- **タイトルとキャラクター作成**: 名前・種族（Human / Sylvan / Stoutkin / Vulpin）・役割（8 種、固定クラスではなく初期能力と装備の出発点）・見た目（ランダム、髪型、髪色、性別）・会社名と旗の色・ワールドシード。3D プレビュー付き。
- **手続き生成の永続世界**: 32 m チャンクを探索した方向へ生成（seed と座標の純関数）。段丘の崖、川（浅瀬・橋）、湖、森、草原、岩場、鉱脈、エーテル結晶、踏み跡の道。開始地点は平坦・水と森の近く・崖の上でない場所を採点で選択。拠点 8 種（遺跡、盗賊の野営地、機械の拠点、交易所、放浪者の野営地、飛行船の残骸、結晶の林、鉱床）を距離に応じた危険度で配置し、開始地点付近には必ず主要な拠点を用意。
- **開拓地**: Hearth（3 段階に拡張）、House、Storehouse、Smelter（鉱石→金属）、Windmill（電力）、Robot Workshop（機械の生産）、Sky Dock、Watchtower（自動射撃）、Stone Wall（ドラッグで列配置）、Outpost（拠点外の建設圏）。配置時に可否と理由を表示、住民が資材を運んで建てる、キャンセルで返金。
- **住民の自律行動**: 伐採・採掘・採集・畑（耕す→植える→育つ→収穫）・運搬・建設・精錬・機械の組立・夜の休息・敵からの避難。優先度（5 系統 × 4 段階）で調整。技能は使うほど上がり（NPC ごとに適性が違う）、レベル・称号・軍の階級が付く。
- **部隊と委任**: Move / Attack（敵・拠点・地点）/ Defend / Explore / Patrol / Escort / Retreat / Auto、撤退閾値スライダー、最大 6 人、住民の徴兵・復帰、新しい小隊の編成。
- **戦闘**: 近接・射撃・投射物・範囲攻撃・会心・装甲、ダウン→回復（負傷）/死亡、戦利品袋（レア以上は光の柱）、名前付きの頭目が固有能力を使う。
- **機械**: Work Bot（住民と同じ仕事、休まない、電力消費）、Walker（二脚の重火力）、Scout Drone（自動偵察）、Repair Drone（回復）、Cargo Airship（探索・交易・自動、飛行で地形を無視）。敵側に Sentry / Turret / War Drone / Machine Warden、商人の飛行船。
- **世界の自律的な動き**: 盗賊の巡回・略奪隊・3 日ごとの拠点拡張（テント増設）・掃討後の再占拠、機械拠点の歩哨再建、商人の飛行船の来訪（余剰の買取と品物の販売）、空き家と食料による移住、放浪者の合流。遠い拠点は休眠して日次処理だけ（簡易シミュレーション）。
- **生成された NPC / アイテム**: 技能 11 種・特性 36 種・癖 85 種・経歴テンプレート、才能の偏り（天才・凡人・戦闘だけ強い等）。アイテム 49 土台 × 素材 × 品質 8 段階 × 接辞 33 種、固有名の異常品。外見 DNA（人物・ロボ・ドローン・飛行船・アイテム）から見た目・肖像・アイコンを決定（画像アートでは種族・装備・性別で絵を選ぶ）。
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
| ヘッドレステスト | `godot --headless --path game res://tests/run_tests.tscn` | 51/51 PASS（2026-09-27 その 3 時点。前回 38、初回 23）。追加: `test_tactics.gd`（態勢の撤退・追撃範囲、技のクールダウンと中断、側面攻撃、セーブ往復、同じ戦闘の態勢別比較）、`test_crossing.gd`（シード 3・7・11・21・42 で近い野営地まで経路があり、3・21・42 では攻撃命令で着いて戦う、橋・階段で経路コストが下がりセーブ後も残る） |
| 決定性 | 同 seed で 900 tick 後の全状態が一致 | PASS |
| セーブ/ロード | 保存→読込で全状態一致、さらに 600 tick 進めても一致（float は 1e-6 で比較） | PASS |
| 長時間 | 10 日間放置（小隊 Auto・飛行船 Auto） | PASS: 負の資源・NaN なし、ユニット 94 以下、探索約 15 万タイル、拠点約 25 発見、約 2 ms/tick |
| 生成 | 品質分布 2 万回、NPC 才能の偏り 500 人、名前の重複、データ相互参照 | PASS |
| 見た目 | 全建物 × 全様式 × 段階、全小物の予算、全アイコンが互いに異なる、全 VFX | PASS |
| AI 層 | 未設定で無効 / ローカルのモックサーバーで実際に HTTP 往復し文章だけ書き換わる | PASS |
| 実プレイ（ウィンドウ） | `tests/probe/explore_day.json`（探索と報告）、`combat_camp.json`（世界シード 11 で野営地を掃討）、`build_windmill.json`（UI クリックで配置→住民が建設、電力 +3.65）、`save_load.json`（F5→F9 で続行）、`night.json`、`showcase.json`、`battle_shots.json`、`crossing.json`（泳ぐ・登る・橋と階段の建設）、`camera_rotate.json`（4 方向・Q/E・ボタン・ねじり・回転後の選択）、`perf_showcase.json` / `perf_exploration_spikes.json`（x1 の計測）、タイトル→作成→開始 | すべて PASS（2026-09-27 その 3 に現行版で再実行） |
| ブラウザ版 | ローカルの Web 書き出しを Chrome（実 GPU）で開き、PC 表示と iPhone 12 横向きのエミュレーションで操作 | タイトル・設定・作成・開始・選択・移動・ピンチ・建設まで動作 |
| 公開版（GitHub Pages） | Actions の書き出し（1 分 12 秒）→ 公開。Chrome で PC 表示: タイトル→作成→開始、吹き出しの表示。iPhone 12 横向きエミュレーション: タイトル→作成→「見た目 2/2」→開始→タッチで探索命令 | 動作（`docs/screenshots/mobile_pages.png`）。ダウンロードは pck 52 MB + wasm 40 MB（転送時は wasm が 10 MB に圧縮される）。キャッシュ後の再読み込みは約 4 秒でタイトル。キャッシュなしの初回は、この PC がメモリ逼迫中だったため一度途中で止まり、タブの再読み込み後に読み込めた（curl では pck を 3.5〜6 秒で取得） |
| ブラウザ版（その 3） | ローカルの Web 書き出しを Chrome で開き、PC 表示（日本語: タイトル→作成「見た目 3/3」→開始→E で回転→建設メニューに川の橋・崖の階段）と iPhone 12 横向きエミュレーション（開始→2 本指ねじりで回転→態勢を「慎重」に変更→吹き出し「距離を保て！」） | 動作、コンソールのエラー 0。回転ボタンの矢印が豆腐になっていたのを見つけて SVG に修正 |

## パフォーマンス（初回計測: Intel Iris Xe、1600×900、Mobile レンダラー、vsync なし。現在の値は冒頭の更新を参照）

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

- 川・崖は泳ぐ・登るで越えられる。自然の湖に囲まれた場所など、泳げない水の向こうには届かない（小隊は通知して待機する）。
- ユニット同士の押し合い（回避）はない。戦闘では同じ目標を別々の角度から囲むので重なりは減ったが、移動中は重なることがある。
- セーブ/ロード後の継続は float の末尾誤差を除いて一致（完全なビット一致ではない）。
- 人物の絵は 124 種（種族 × 見た目 × 性別 × 3 種）。建物の絵は 1 方向のみで、±90° のカメラでは左右反転で代用している（扉や看板の位置が変わる）。
- 世界の広さは開始点から ±320 m（設定値）。
- スマホは実機未確認（デスクトップ Chrome のエミュレーションのみ）。

## 変更ファイル（新規プロジェクト。主要なもの）

2026-09-27（その 3）の更新で追加・変更したもの:

- カメラの回転: `game/src/view/{camera_rig,input_controller}.gd`、`game/src/visual/{look_dev,building_visual,building_visuals,sprite_unit_visual,prop_meshes}.gd`、`game/src/visual/shaders/sprite_*`、`game/src/ui/{hud,minimap}.gd`、`game/assets/icons/ui_rotate_{left,right}.svg`、`game/data/i18n/camera-*.json`
- 住民の見た目 v3: `tools/art/{make_prompts.py,process.py}`、`art_src/prompts.json`、`game/assets/{sprites/chars,portraits}/*_v3.png`、`game/data/art/*.json`、`game/src/visual/sprite_library.gd`、`game/src/sim/{world,faction_ai}.gd`（絵の割り当て）、`game/src/ui/roster_panel.gd`
- 戦術: `game/src/sim/{squad,squad_ai,unit,combat}.gd`、`game/data/generation/tactics_abilities.json`、`game/src/ui/squad_panel.gd`、`game/data/i18n/tactics-*.json`、`game/src/view/chatter.gd`、`game/data/i18n/chatter-*.json`
- 川と崖: `game/src/sim/{world,save_game}.gd`、`game/src/world/{tiles,world_gen}.gd`、`game/data/buildings/buildings.json`、`game/src/visual/world/bld_frontier.gd`、`game/src/ui/build_menu.gd`、`game/assets/icons/bld_{bridge_segment,cliff_stairs}.svg`、`game/data/i18n/crossing-*.json`
- カクつき: `game/src/view/world_view.gd`（拠点の見た目を 1 フレーム 1 棟）、`game/src/ui/minimap.gd`、`game/src/visual/vfx.gd`
- ブラウザ版: `game/web_shell.html`、`game/export_presets.cfg`（PWA）、`tools/web/apply_import_presets.py` と各 `.import`、`game/src/ui/ui_theme.gd`（太字の合成）、`game/assets/fonts/`（太字を削除）
- テストと確認: `game/tests/{test_tactics,test_crossing,run_tests}.gd`、`game/tests/probe/{crossing,camera_*,showcase_camera135,perf_*}.json`

2026-09-27（その 2）の更新で追加・変更したもの:

- 音と設定:
  - `tools/audio/compose_bgm.py`、`game/assets/audio/`（全て OGG）、`game/default_bus_layout.tres`
  - `game/src/core/{sfx,settings,quality}.gd`、`game/src/ui/{settings_panel,pause_menu,title_screen}.gd`
- スマホとブラウザ:
  - `game/src/core/app.gd`（UI の自動拡大・タッチ判定）
  - `game/src/view/{input_controller,camera_rig,game}.gd`
  - `game/src/ui/{hud,info_panel,squad_panel,build_menu}.gd`
  - `game/export_presets.cfg`、`game/web_shell.html`、`tools/web/`、`.github/workflows/pages.yml`
- 住民の見た目の種類:
  - `tools/art/{make_prompts.py,process.py}`、`art_src/prompts.json`
  - `game/assets/{sprites/chars,portraits}/*_v2.png`、`game/data/art/{sprites,portraits}.json`
  - `game/src/visual/sprite_library.gd`
- 戦闘と角度: `game/src/sim/combat.gd`、`game/src/visual/{vfx,sprite_unit_visual,look_dev,building_visual}.gd`、`game/src/visual/shaders/*`、`game/src/view/{world_view,chunk_view,unit_view}.gd`
- 吹き出し: `game/src/view/chatter.gd`、`game/src/ui/speech_bubbles.gd`、`game/data/i18n/chatter-*.json`
- 小隊の攻撃経路: `game/src/sim/squad_ai.gd`
- テスト: `game/tests/{test_chatter,test_painted_art,test_i18n}.gd`、`game/tests/gallery_units.gd`

2026-09-27 の更新で追加・変更したもの:

- 日本語対応:
  - `game/src/core/loc.gd`（autoload `Loc`）
  - `game/data/i18n/`（`ja.json`・`en.json`・`sim-*.json`・`gen-*.json`・`ja/**` のデータ表訳）
  - `game/assets/fonts/CogwildCJK-*.otf` と `LICENSE-NotoCJK.txt`、`tools/subset_japanese_fonts.py`
  - UI 全般（`game/src/ui/*.gd`、`game/src/view/{game,input_controller}.gd`）
  - シミュレーションの通知の key 化（`game/src/sim/*.gd`）
  - 生成器のテンプレート ID の保存（`game/src/gen/*.gd`）
  - `game/tests/test_i18n.gd`
- 画像生成アート:
  - `tools/art/{make_prompts.py,process.py,overrides.json}`、`art_src/prompts.json`
  - `game/assets/{sprites,portraits,textures,ui}/`、`game/data/art/*.json`
  - `game/src/visual/{sprite_library.gd,sprite_unit_visual.gd}`、`game/src/visual/shaders/sprite_*.gdshader*`、`terrain.gdshader`
  - `unit_visual_factory.gd`、`building_visual(s).gd`、`portrait_renderer.gd`、`icons.gd`、`mesh_kit.gd`
  - `game/src/view/{chunk_view,unit_view,world_view}.gd`
  - `game/tests/test_painted_art.gd`、`docs/art_pipeline.md`

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

Git: 新規リポジトリに初回コミット `e87e29b`（以降の修正は追加コミット）。GitHub: https://github.com/dma-cmyk/cogwild-frontier

## スクリーンショット

`docs/screenshots/`（画像生成アート。2026-09-27 その 3 に現行版で撮り直し）: `title.png`, `character_creation.png`, `settlement_day.png`（商人の交易パネル・技の通知）, `settlement_evening.png`（吹き出し）, `night.png`, `construction.png`（建設中の風車）, `windmill_built_via_ui.png`, `build_menu.png`（日本語、川の橋・崖の階段）, `bandit_camp.png`, `combat_retreat.png`（撤退のかけ声）, `speech_battle.png`（戦闘中の吹き出し）, `speech_ja.png`, `speech_en.png`, `speech_mobile.png`（1170×540）, `world_overview_zoomed_out.png`, `world_map_seed11.png`。

その 3 で追加: `camera_rotated.png`（135° から見た開拓地、建物は左右反転）, `crossing_swim.png`, `crossing_climb.png`, `crossing_bridge.png`, `crossing_stairs.png`, `tactics_abilities.png`（盾打ち・狙い撃ちの通知と態勢・隊形の選択）, `roster_faces.png`（12 人の肖像がすべて違う）。

人物の v1 / v2 / v3 の比較は `docs/screenshots/dev/units_variants.png`。

公開版をスマホ表示（iPhone 12 横向きのエミュレーション）で遊んでいる画面: `docs/screenshots/mobile_pages.png`。

`docs/screenshots/i18n/`: `ja_title.png`, `ja_creation.png`, `ja_new_game.png`, `ja_hud.png`, `ja_pause.png`, `en_hud.png`。

旧・低ポリ表示の画面は `docs/screenshots/dev/lowpoly_*.png`、制作中の確認用も `docs/screenshots/dev/`。
