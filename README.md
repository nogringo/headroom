# Headroom

**Get a thought out of your head in seconds.**

Headroom is a sticky note for the things that clutter your mind: errands, ideas, reminders. Write one down, press Enter, and it joins a list sorted by day. If you want, an AI of your choice sorts the list by theme and points out what could be merged or deleted. It runs on Android, iOS, macOS, Windows, Linux and the web, and keeps everything on your device.

## Features

- **Write and move on.** Type on the note and press Enter. On a computer, Shift+Enter starts a new line. Thoughts are listed under the day they were noted: Today, Yesterday, then the weekday and date.
- **Images.** Paste one or several images into a thought with Cmd/Ctrl+V, or with "Paste image" in the field's menu. Tap an image to see it full screen, go through a thought's images with the arrow keys, and copy one back out with Cmd/Ctrl+C, a right-click or a long press.
- **Edit and delete.** Tap a thought to edit it. Swipe it away on a touch screen, or use the delete button that shows on hover on a computer. Undo brings it back.
- **Themes.** With AI tidying on, each new thought gets a theme, and a sidebar opens one theme at a time so the rest of the list stays out of sight. The app reopens on the theme you left. When the AI files a thought in the wrong place, pick its theme yourself in the edit dialog: the AI leaves it there and sorts similar thoughts the same way. The pencil beside the open theme renames it, and giving it another theme's name merges the two. Themes work without the AI too.
- **Clean-up suggestions.** The AI spots thoughts that repeat each other and writes the one that would replace them, and flags thoughts that are out of date, such as an appointment whose day has passed. Nothing changes until you accept, and a declined suggestion is not offered again.
- **Backup.** Save a copy of every thought and image as a zip, wherever you like, and restore it on any device. A restore adds the thoughts that are missing and deletes nothing.
- **In English and French.**

## AI tidying

Tidying is off until you set it up from the sidebar. It works with any service that speaks OpenAI's Chat Completions API, including a model running on your own computer. The dialog has shortcuts for:

| Service | API address |
| --- | --- |
| OpenAI | `https://api.openai.com/v1` |
| Claude | `https://api.anthropic.com/v1` |
| Gemini | `https://generativelanguage.googleapis.com/v1beta/openai` |
| Mistral | `https://api.mistral.ai/v1` |
| DeepSeek | `https://api.deepseek.com` |
| OpenRouter | `https://openrouter.ai/api/v1` |
| Z.ai | `https://api.z.ai/api/paas/v4` (not on the web, it refuses calls from a browser) |
| Ollama | `http://localhost:11434/v1` |

Any other address works too. Enter it with an API key (not needed for a local model) and pick a model from the list the service offers.

Once set up, tidying runs on its own: two seconds after you note or edit something, and at least once a day to catch what went out of date. Each pass reads the whole list and gives a theme to up to 50 thoughts. When the service fails, tidying pauses and says why (unreachable, key refused, limit or credit used up), with a button to try again.

Only the text of your thoughts is sent to the service. Images stay on the device.

Z.ai needs a pay-as-you-go key: GLM Coding Plan keys are limited to the tools Z.ai supports.

## Where your thoughts live

Nothing leaves the device except the text sent to the AI you set up.

- **Android, iOS, macOS, Windows, Linux:** `thoughts.json`, an `images/` folder and a few small JSON files for the settings, in the app's support directory. Each file is written to a temporary file first, then renamed, so a crash never leaves it half written.
- **Web:** the thoughts and settings in `localStorage`, the images in IndexedDB.

Images are named after a SHA-256 of their content, so the same image pasted twice is stored once. The AI's API key is kept with the other settings, unencrypted.

### Backup format

A backup is a zip named `headroom-YYYY-MM-DD.zip`, laid out like the storage:

- `thoughts.json`: every thought, with its text, images, date and theme, and whether you chose that theme.
- `images/`: the images, with an extension so they open from the unzipped copy.
- `ai.json`: the AI's address and model. Never the API key, which has no place in a file left on a cloud drive.
- `tidy.json`: the clean-ups you declined.

## Credits

The app's typeface is [Recursive](https://github.com/arrowtype/recursive), under the SIL Open Font License (`assets/fonts/OFL.txt`).

## License

[MIT](LICENSE)
