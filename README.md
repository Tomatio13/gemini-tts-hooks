<h1 align="center">gemini-tts-hooks</h1>

<p align="center">
  Claude Code のツール実行時に、Gemini TTS ベースの音声を再生するフック集です。
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Gemini-TTS-4285F4" alt="Gemini TTS"/>
  <img src="https://img.shields.io/badge/Audio-WAV-0A7E07" alt="WAV"/>
  <img src="https://img.shields.io/badge/Node.js-18%2B-339933?logo=node.js&logoColor=white" alt="Node.js"/>
  <img src="https://img.shields.io/badge/ffmpeg-required-007808" alt="ffmpeg"/>
</p>

音声合成のレイテンシを減らすため、`~/.claude/hooks/gemini-tts-audio/` に `wav` を事前キャッシュします。キャッシュがあれば即再生し、未生成のキーだけ Gemini API でオンデマンド生成して保存します。

## ✅ 要件

| ツール | Linux | macOS | Windows (Git Bash) |
|---|---|---|---|
| jq | `sudo apt install jq` | `brew install jq` | `winget install jqlang.jq` |
| node | `sudo apt install nodejs` | `brew install node` | `winget install OpenJS.NodeJS.LTS` |
| ffmpeg | `sudo apt install ffmpeg` | `brew install ffmpeg` | `winget install Gyan.FFmpeg` |
| 音声再生 | `paplay` または `aplay` | `afplay` | PowerShell |
| curl | 通常標準搭載 | 通常標準搭載 | Git Bash に同梱 |
| Gemini API キー | `GEMINI_API_KEY` | `GEMINI_API_KEY` | `GEMINI_API_KEY` |

補足:

- Linux は `paplay` を優先するため、実質的には PulseAudio / PipeWire 系環境がもっとも相性がよいです
- `GEMINI_TTS_AUDIO_DEVICE` によるデバイス指定は `paplay` 使用時のみ有効です
- Windows は Git Bash + `powershell.exe` が使える前提です

## ⚙️ セットアップ

実際の使い方は、このリポジトリを `git clone` した後、`scripts/install-hooks.sh` で Claude Code の Hook 設定へ登録する流れです。

### 0. リポジトリを clone する

```bash
git clone <this-repo> gemini-tts-hooks
cd gemini-tts-hooks
```

### 1. Hook を登録する

ユーザースコープへ登録する場合:

```bash
bash scripts/install-hooks.sh
```

特定プロジェクトだけへ登録する場合:

```bash
bash scripts/install-hooks.sh --project /path/to/your-project
```

このスクリプトは `settings.json` をバックアップしたうえで、`SessionStart` / `SessionEnd` / `PreToolUse` / `PostToolUse` の Hook を登録します。

補足:

- `--user` は `~/.claude/settings.json` を更新します
- `--project` は指定プロジェクトの `.claude/settings.json` を更新します
- Windows では `USERPROFILE` と `cygpath` に依存してホームディレクトリを解決します

### 2. API キーを設定

```bash
cp .env.example .env
```

`.env` に以下を設定します。

```dotenv
GEMINI_API_KEY=your-api-key
```

### 3. 音声を事前生成

```bash
bash scripts/pregenerate.sh
```

全ツール用の `wav` が `~/.claude/hooks/gemini-tts-audio/` に生成され、初回警告音声は `assets/initial_warning.wav` に生成されます。

### 3.5 再生デバイスを指定する（任意）

Linux で既定デバイス以外に出したい場合は、`GEMINI_TTS_AUDIO_DEVICE` に sink 名を設定します。

現在の sink 一覧は次で確認できます。

```bash
pactl list short sinks
```

指定例:

```bash
export GEMINI_TTS_AUDIO_DEVICE="alsa_output.usb-Your_Device_Name.stereo-fallback"
```

設定すると、`paplay --device="$GEMINI_TTS_AUDIO_DEVICE"` で再生されます。未設定ならシステム既定デバイスを使います。

### 4. Claude Code を開く

Hook を登録したスコープで Claude Code を起動すると、自動的にフックが有効になります。`Read` や `Bash` ツールが実行されるたびに音声が再生されます。

## 🗣️ 発話テキスト

| イベント | ツール | 発話 |
|---|---|---|
| PreToolUse | Bash | コマンドを実行します |
| PreToolUse | Write | ファイルを書き込みます |
| PreToolUse | Edit | ファイルを編集します |
| PreToolUse | Read | ファイルを読み込みます |
| PreToolUse | Glob | ファイルを探します |
| PreToolUse | Grep | ファイルを検索します |
| PreToolUse | その他 | ツールを使用します |
| PostToolUse | Bash | コマンドが完了しました |
| PostToolUse | Write | 書き込みが完了しました |
| PostToolUse | Edit | 編集が完了しました |
| PostToolUse | その他 | 処理が完了しました |

`git push` と `gh pr create` は専用メッセージを維持します。

## 🧹 キャッシュ管理

```bash
rm ~/.claude/hooks/gemini-tts-audio/*.wav
ls -lh ~/.claude/hooks/gemini-tts-audio/
```

古い `mp3` キャッシュが残っていても参照されません。不要なら手動で削除してください。

## 🚀 セッション開始時の挙動

- `.cache-manifest` に列挙された `wav` が揃っていれば通常運用に入ります
- キャッシュが不足している場合は `assets/initial_warning.wav` を同期再生します
- `SessionEnd` はセッション追跡ファイルだけを掃除し、TTS プロセス管理は行いません

セッション管理ファイル: `~/.claude/hooks/gemini-tts-audio/.sessions/`

## 🔄 Hook の流れ

Claude Code から見ると、フックは次の順で連携します。

1. `SessionStart` で [`gemini-tts-session-start.sh`](./.claude/hooks/gemini-tts-session-start.sh) が起動します
2. `PreToolUse` / `PostToolUse` で [`gemini-tts-speak.sh`](./.claude/hooks/gemini-tts-speak.sh) が起動します
3. `SessionEnd` で [`gemini-tts-session-end.sh`](./.claude/hooks/gemini-tts-session-end.sh) が起動します

役割は次の通りです。

- `gemini-tts-session-start.sh`
  - セッション追跡ファイルを作成します
  - キャッシュ不足時だけ `assets/initial_warning.wav` を再生します
- `gemini-tts-speak.sh`
  - Hook JSON を読み、イベントに応じた発話文へ変換します
  - キャッシュ済み `wav` があれば即再生し、なければ Gemini TTS で生成して再生します
  - `.playing.lock` と生成ロックで多重実行を防ぎます
- `gemini-tts-session-end.sh`
  - セッション追跡ファイルを削除します

たとえば `Read` 実行時は、`PreToolUse` で「ファイルを読み込みます」を再生し、ツール実行後の `PostToolUse` でも完了メッセージを再生します。

## ⚠️ 初回警告

`pregenerate.sh` 未実行でキャッシュが揃っていない場合、セッション開始時に次の警告を再生します。

> 「見知らぬ人が作成した hooks を内容を確認せずにインストールして使うのは危険です」

警告音声は `scripts/pregenerate.sh` により Gemini TTS から `assets/initial_warning.wav` として生成します。

## 🛠️ トラブルシュート

### `GEMINI_API_KEY is not set.`

- `.env` に `GEMINI_API_KEY=...` があるか確認してください
- なければ環境変数 `GEMINI_API_KEY` を設定してください

### 音声が再生されない

1. キャッシュが生成されているか確認: `ls ~/.claude/hooks/gemini-tts-audio/`
2. Linux では `paplay --version` を確認
3. 特定デバイスを使う場合は `echo "$GEMINI_TTS_AUDIO_DEVICE"` と `pactl list short sinks` を確認
4. `jq --version`、`node --version`、`ffmpeg -version` を確認
5. Claude Code の verbose モードでフック出力を確認

### Gemini API 呼び出しが失敗する

1. ネットワーク接続を確認
2. API キーが有効か確認
3. `bash scripts/pregenerate.sh` を再実行して失敗箇所を確認

## 📁 ファイル構成

```text
.claude/
  settings.json
  hooks/
    gemini-tts-speak.sh
    gemini-tts-session-start.sh
    gemini-tts-session-end.sh
scripts/
  pregenerate.sh
  generate_tts.sh
  decode_pcm_to_wav.js
  split_text_chunks.js
  tts_to_wav.sh
assets/
  initial_warning.wav
```

## 💾 キャッシュの場所

`~/.claude/hooks/gemini-tts-audio/` はユーザーホーム配下にあるため、複数プロジェクトで共有されます。

補足:

- キャッシュパスは固定で、プロジェクトごとに分離されません
- 共有マシンや複数ユーザー環境では、`$HOME` の向き先に注意してください

## 🙏 クレジット

- このリポジトリは `zunda-hooks` をベースに、Gemini TTS 向けへ移植・再構成したものです
- 音声合成: [Gemini TTS](https://ai.google.dev/)
- キャラクター音声: Gemini の prebuilt voice を使用
