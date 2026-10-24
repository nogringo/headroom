# Headroom

**Get a thought out of your head in seconds.**

Headroom is a sticky note for the things that clutter your mind: errands, ideas, reminders. Write one down, press Enter, and it joins a list sorted by day. If you want, an AI of your choice sorts each thought by theme as you note it, gives a long one a title and splits a task into subtasks, and, when you ask, points out what could be merged or deleted. It runs on Android, iOS, macOS, Windows, Linux and the web, and keeps everything on your device.

## Features

- **Write and move on.** Type on the note and press Enter. On a computer, Shift+Enter starts a new line, and `/` brings you back to the note from anywhere in the app, as does Cmd+N (Ctrl+N on Windows and Linux) outside a browser. Thoughts are listed under the day they were noted: Today, Yesterday, then the weekday and date.
- **Images.** Paste one or several images into a thought with Cmd/Ctrl+V, or with "Paste image" in the field's menu. Tap an image to see it full screen, go through a thought's images with the arrow keys, and copy one back out with Cmd/Ctrl+C, a right-click or a long press.
- **Edit and delete.** Tap a thought to edit it. Swipe it away on a touch screen, or use the delete button that shows on hover on a computer. Undo brings it back.
- **Right-click menu.** On a computer, right-click a thought, or press the menu key or Shift+F10 once it has the focus, to edit it, copy its text, change its themes, pin it, move it within the open theme or delete it. Right-clicked on an image, the menu also copies that image. A theme in the sidebar has a menu too, to rename it, move it or delete it. Deleting a theme keeps its thoughts, and Undo puts it back.
- **Themes.** With AI tidying on, each new thought gets one theme or more, and a sidebar opens one theme at a time so the rest of the list stays out of sight. Each theme there shows how many thoughts it holds. A thought in several themes shows in each. The app reopens on the theme you left. The list of every thought shows each one's themes under it, and an open theme shows the others a thought is in. When the AI files a thought in the wrong place, tap its themes, or open the thought, and tick the right ones: the AI leaves them as they are and sorts similar thoughts the same way. The pencil beside the open theme renames it, and giving it another theme's name merges the two. Drag a theme to put it elsewhere in the sidebar, after a long press on a touch screen. New themes come after the ones you placed. The thoughts of an open theme move the same way, each theme keeping its own order, and a new one arrives at the top. The list of every thought stays sorted by day. Themes work without the AI too.
- **Pin.** A pinned thought stays in sight above the others: under Pinned at the top of the list of every thought, and at the top of each of its themes, where a new thought arrives just below it. Pin one from its right-click menu, or open it and press the pin. Press the pin shown on it to unpin it. In a theme, the pinned thoughts move among themselves and the others among themselves.
- **Titles and subtasks.** With AI tidying on, a long thought gets a short title, listed in its place. Tap it to read and edit the thought as you wrote it. A task with several steps, or a list of things to get, gets subtasks to tick off right from the list. A thought you edit keeps its title and subtasks.
- **Clean-up suggestions.** When you ask, from "Clean up" in the sidebar, the AI spots thoughts that repeat each other and writes the one that would replace them, and flags thoughts that are out of date, such as an appointment whose day has passed. Nothing changes until you accept, and a declined suggestion is not offered again.
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

Once set up, the AI is asked once about each thought you note. It gets that thought, the names of your themes and the thoughts whose themes you chose, but not the rest of the list. Editing a thought asks nothing, nor does opening the app, except to catch up on thoughts noted while the service was out of reach. Only a clean-up reads the whole list, and only when you ask for one. When the service fails, tidying pauses and says why (unreachable, key refused, limit or credit used up), with a button to try again.

Reasoning models think before they answer, and the service bills that thinking. A model that answers straight away is enough here and costs much less.

Only the text of your thoughts is sent to the service. Images stay on the device.

Z.ai needs a pay-as-you-go key: GLM Coding Plan keys are limited to the tools Z.ai supports.

## Where your thoughts live

Nothing leaves the device except the text sent to the AI you set up.

- **Android, iOS, macOS, Windows, Linux:** `thoughts.json`, an `images/` folder and a few small JSON files for the settings, in the app's support directory. Each file is written to a temporary file first, then renamed, so a crash never leaves it half written.
- **Web:** the thoughts and settings in `localStorage`, the images in IndexedDB.

Images are named after a SHA-256 of their content, so the same image pasted twice is stored once. The AI's API key is kept with the other settings, unencrypted.

### Backup format

A backup is a zip named `headroom-YYYY-MM-DD.zip`, laid out like the storage:

- `thoughts.json`: every thought, with its text, images, date and themes, whether you chose them, whether you pinned it, the title and subtasks the AI gave it and which you ticked off, and its place in each theme once you moved it.
- `images/`: the images, with an extension so they open from the unzipped copy.
- `ai.json`: the AI's address and model. Never the API key, which has no place in a file left on a cloud drive.
- `tidy.json`: the clean-ups you declined.
- `list.json`: the order you put the themes in. A restore keeps the order already on the device and places the themes it lacks after it.

## Credits

The app's typeface is [Recursive](https://github.com/arrowtype/recursive), under the SIL Open Font License (`assets/fonts/OFL.txt`).

## License

[MIT](LICENSE)
