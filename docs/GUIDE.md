# FUZIX MZ-2500 port: guide (日本語)

## 1. できていること
- Sharp MZ-2500 向けの FUZIX(Z80)。ルート FS は SASI HDD とブート可能なフロッピー(2DD)の両方に置ける。
- カーネルは全コード手書きアセンブラ(`Kernel/platform/platform-mz2500/*.s`)。C 実装の原型は `c-reference/` に参考として残してある(ビルドされない)。
- 動作確認はエミュレータ(MZ-2500 web emulator のネイティブ CLI)。実機は未確認。
- 機能: マルチプロセス(fork/exec/wait、シグナル、パイプ)、V7 sh、約 60 個のコマンド、権限チェック、mount/umount、ディスクのフォーマット/コピー(`fdformat`、`fdcopy`)、EMM(MZ-1R37)をバッファキャッシュ/メモリに利用、ログイン付き起動(`inittab.login`)。
- 自動テスト: `mz2500/tools/regress.sh`(EMM あり / `--no-emm`)、`fdtest.sh`(フロッピー)、`fscheck.sh`(fsck)。単体テスト(`Applications/util/`): `vtt`、`edge`〜`edge7`(errno、fd 上限、パイプ、シグナル、ディスクフル、inode 枯渇、アドレス検証、fork 枯渇)。

## 2. 必要なもの(同梱しない)
- ROM はすべて利用者所有のものを使う(IPL ROM、SASI のオプション ROM `FILE.ROM` など)。配布物・リポジトリには含めない。
- 実機でのブート: `fdboot.d88` を実フロッピーに書く。HDD 起動はオプション ROM 経由。

## 3. ビルドと実行
README の Quick start を参照。設定は `mz2500/tools/env.sh`(`MZ_FUZIX`、`MZ_EMU`、`MZ_ROMDIR`、`MZ_SASI_ROM`、`MZ_TOOLCHAIN`)。

- `mz2500/tools/build_userland.sh`: ホストツール(mkfs、ucp、fsck)、ライブラリ、アプリケーションをビルド。
- `mz2500/tools/mkroot.sh 出力.img`: ルート FS(`EXTRA=名前` で追加プログラム、`ISIZE`/`FSIZE` でサイズ)。HDD 化は `mkhdd.py`。
- `mz2500/run_hdd.sh`: カーネルをビルドして `root.hdf` を作り、エミュレータで起動。`Free memory begins at:` が出る。
- `mz2500/tools/mkfdsys.sh`: ブート可能なフロッピー `fdboot.d88`。ログイン付きは `INITTAB=inittab.login ./tools/mkfdsys.sh`。
- ブートプロンプト: `hda`(HDD)、`hda rw`、`fd0 rw`(フロッピー)。
- `tools/profsum.py`、`emu-profiler.patch`: エミュレータに PC プロファイラを足すパッチと、結果の集計。

## 4. 構成
- 窓 7(E000〜)は固定のコモン領域、窓 0〜6 を B4h/B5h でバンク切替。カーネルバンクは 0100〜BFFF(窓 6 はテキスト VRAM)。ユーザーバンクは複数ページ(EMM のページも使う)。
- 割り込み: 8253 ch0 による 50Hz タイマ、キーボード。割り込み状態は `_int_disabled` で自前管理(di/ei を直接使うコードは要注意)。
- ドライバ: `devhd_asm.s` + `sasi.s`(SASI)、`devfd.s`(MB8877)、`devtty_asm.s` + `vt_asm.s` + `video.s`(テキスト VRAM、キーボード、VT52 風)、`emm.s`。
- ソースの一覧は Makefile の `ASRCS` と `fuzix.lnk`。

## 5. 性能の目安(エミュレータ)
- ディスク書込みは SASI のポーリング転送が支配的で、512B ブロックあたり約 1 フレーム。
- 書込みのキャッシュ/遅延化は未実装(バッファは 6 面)。

## 6. 既知の制約・癖
- upstream の癖を保持: fcntl の F_SETFD/F_DUPFD、flock の shared→exclusive、sync がスーパーブロックのカウンタを書かない。
- inode 枯渇時のエラーは ENFILE(upstream と同じ)。
- 修正した upstream の不具合: SIGTERM が配送されない、読み手のいないパイプへの write が成功する、既存ファイルを開くときの権限チェック欠落。
- 実機未検証: Ctrl/CapsLock/キーリピート、SASI/FDC/EMM のタイミング、B5h の自動インクリメント(`REALHW-CHECKLIST.md` を参照)。

## 7. 次の候補
- 実機での検証(最優先)。
- 書込みの遅延化・キャッシュ拡張、サイズ最適化。
