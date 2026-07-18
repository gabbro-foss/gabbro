# Auto-type (Linux) and Autofill (Android)

Gabbro can type a saved login into another app for you, so you never
copy-paste a password. The two platforms work differently.

| | Linux | Android |
|---|---|---|
| Name | Auto-type | Autofill |
| You trigger it with | a keyboard shortcut you choose | tapping the login field |
| Setup needed | bind a key (below) | enable Gabbro as the autofill service |

---

## Linux — auto-type

### What it does

You open a login in Gabbro, switch to the app or website that wants it,
press your shortcut, and Gabbro types the username and password into the
focused window.

The password never leaves Gabbro's Rust core as text you can copy — it goes
straight to the keyboard.

### Requirements

- An **X11** session. Wayland does not allow one app to type into another, so
  auto-type cannot work there. (Check with `echo $XDG_SESSION_TYPE`.)
- Gabbro **running and unlocked**.
- A login **open** in Gabbro — that open entry is what gets typed. If nothing
  is open, the shortcut does nothing.

### 1. Find `gabbro-autotype`

This is a small program shipped alongside the app. It does nothing on its own;
it just tells the running Gabbro to type.

If you installed from a release tarball, it sits next to the app:

```
<where-you-unpacked>/bundle/gabbro-autotype
```

If you built from source, it is at `rust/target/release/gabbro-autotype`.

Note the full path — you need it in the next step.

### 2. Bind it to a key

**qtile** — add to the `keys` list in `~/.config/qtile/config.py`:

```python
Key([mod, "control"], "g", lazy.spawn("/full/path/to/gabbro-autotype")),
```

Reload qtile afterwards.

**Cinnamon / Linux Mint** — Menu → **Keyboard** → **Shortcuts** →
**Custom Shortcuts** → **Add custom shortcut**:

- Name: `Gabbro auto-type`
- Command: the full path to `gabbro-autotype`

Click the new entry, click **unassigned**, and press the key combination you
want.

**Other desktops** (GNOME, KDE, XFCE) all have an equivalent custom-shortcut
screen; point it at the same path.

### 3. Use it

1. Open the login in Gabbro.
2. Click into the username field of the app or site you are signing in to.
3. Press your shortcut.

If the login has no username, its email is typed instead.

### If nothing happens

- **Gabbro is locked or closed** — auto-type only works while it is running and
  unlocked.
- **No login open in Gabbro** — open one first.
- **You are on Wayland** — see Requirements above.
- **Wrong path** — run the path from a terminal. If it prints
  `no running Gabbro to trigger`, the path is right and Gabbro is not running.
  If the shell says "no such file", the path is wrong.

---

## Android — autofill

### What it does

When an app or website shows a login field, Android offers Gabbro's matching
saved logins above the keyboard. You tap one and the fields fill.

### Enable it

Settings → **Passwords, passkeys & accounts** → **Autofill service** →
**Gabbro**.

The exact wording varies by Android version and by GrapheneOS; search Settings
for "autofill" if you cannot find it.

### Use it

1. Open the app or site and tap the username or password field.
2. Gabbro appears — unlock it if prompted.
3. Pick the login. Both fields fill.

Gabbro matches websites on the registrable domain, so a login saved for
`example.com` is offered on `login.example.com`.

### If nothing appears

- **No saved login matches** — Gabbro says so rather than filling the wrong
  thing.
- **Another password manager is the autofill service** — Android allows only
  one at a time.
- **The app blocks autofill** — some banking apps do this deliberately.
