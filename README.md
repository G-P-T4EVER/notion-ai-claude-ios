# Notion AI для iOS в облике Claude

Неофициальный клиент **Notion AI** для iPhone и iPad, у которого UI/UX полностью повторяет клиент Claude: тёмная палитра, ораньжевая звезда-старбёрст, композер с `Type / for skills`, переключатель **Chat / Cowork**, пилюля модели, чипсы `Write / Learn / Code / Life stuff / Claude's choice`, настройки со `Chat font`, `Motion`, `Reflect`, `Time and focus` и разделом `Customize`.

Главная цель — **старые iOS: от 14.0 до 16.6.1**. Поэтому весь интерфейс написан на UIKit (никакого SwiftUI и сторонних зависимостей), а сборка выходит неподписанной в форматах `.ipa` и `.tipa`.

---

## Что умеет

| Возможность | Как сделано |
|---|---|
| Вход | Настоящая страница `notion.so/login` в `WKWebView`: почта, Google, Apple, SSO. Из cookie забирается `token_v2` и кладётся в Keychain |
| Чат с Notion AI | Потоковый ответ (NDJSON/SSE), «живой» курсор, кнопка Stop, повтор ответа, копирование |
| Cowork | Перед ответом выполняется поиск по вашему воркспейсу, найденные страницы передаются модели как контекст, шаги показываются строками активности |
| Модели | Sonnet 5 · High, Opus 5 · High, Haiku 4.5 · Fast (выбор в композере и в Capabilities) |
| История | Локальная база `conversations.json`, поиск, переименование, свайп-удаление, авто-заголовки |
| Воркспейс | Поиск страниц, просмотр страницы внутри приложения по сессионной cookie, кнопка «спросить про страницу» |
| Вставка ссылок | «Reference a page» добавляет ссылку на страницу в композер |
| Диктовка | `SFSpeechRecognizer` + `AVAudioEngine`, по возможности on-device, микрофон пульсирует по уровню звука |
| Markdown | Свой лёгкий рендерер: заголовки, списки, цитаты, код, `inline code`, ссылки |
| Настройки | General, Account, Privacy, Billing, Capabilities, Memory, Reflect, Time and focus, Claude Code + Skills, Connectors, Plugins |
| Reflect | Считается локально: самый активный день, пиковый час, всего разговоров, график за неделю/месяц/квартал |
| Доступность | 4 варианта шрифта чата (включая Dyslexic friendly), Dynamic Type, Reduce animation, хаптика |

---

## Как получить .ipa / .tipa (Xcode и macOS не нужны)

Сборку делает GitHub Actions.

1. Залейте этот репозиторий в GitHub (ветка `main`).
2. Откройте вкладку **Actions** → workflow **Build unsigned IPA** → при необходимости **Run workflow**.
3. Через несколько минут файлы будут:
   - в **Artifacts** архива сборки: `NotionClaude-unsigned` (внутри `NotionClaude.ipa` и `NotionClaude.tipa`);
   - в **Releases**: тег `build-<номер запуска>` обновляется при каждом пуше в `main`. Если поставить тег `v1.0.0`, выйдет обычный релиз.

### Установка

- **TrollStore** (iOS 14.0–16.6.1 с поддерживаемым эксплойтом) — поставьте `NotionClaude.tipa`, подпись не нужна.
- **Sideloadly / AltStore / ESign** — поставьте `NotionClaude.ipa`, он подпишется вашим Apple ID.
- Bundle ID: `com.sa1nt.notionclaude`.

---

## Локальная сборка (если появится Mac)

```bash
brew install xcodegen
python3 Tools/make_icons.py      # генерирует Assets.xcassets
xcodegen generate
open NotionClaude.xcodeproj
```

Минимальная версия iOS — 14.0, Swift 5, iPhone + iPad.

---

## Структура

```
Sources/App         AppDelegate, SceneDelegate, RootController (чат + drawer)
Sources/Auth        вход через официальную страницу Notion
Sources/Chat        транскрипт, композер, ячейки сообщений, empty state, диктовка, Markdown
Sources/Sidebar     история чатов, поиск, аккаунт
Sources/Workspace   поиск по воркспейсу и просмотр страниц
Sources/Settings    все разделы настроек и экран Reflect
Sources/Network     сессия, /api/v3, стриминг ответа
Sources/Storage     Keychain, настройки, история
Sources/Design      палитра, шрифты, старбёрст
Tools/make_icons.py генерация иконки и цветов
.github/workflows   сборка .ipa/.tipa
```

---

## Честные ограничения

- **Приватное API.** Notion не публикует API для своего AI. Клиент ходит в `/api/v3` так же, как веб-клиент. Если Notion переименует эндпоинт, ответы перестанут приходить — путь меняется в **Settings → Capabilities → AI endpoint path**, без пересборки.
- **Шрифты.** Фирменные гарнитуры Anthropic нельзя распространять, поэтому `Anthropic Serif` и `Anthropic Sans` собраны на системных аналогах (serif / sans).
- **Voice mode.** Диктовка работает, полноценный дуплексный голос требует realtime-эндпоинта, которого у Notion публично нет.
- **Claude Code и Plugins** существуют только на десктопе — разделы оставлены, чтобы дерево настроек совпадало.
- Проект неофициальный и не связан ни с Notion, ни с Anthropic. Товарные знаки принадлежат владельцам.

## Лицензия

MIT, см. `LICENSE`.
