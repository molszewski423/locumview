# LocumView desktop: getting around

Draft help content for LocumView users. It will later become the in-desktop help (GNOME Tour / Help pages) once the desktop design is final. Source of truth for the shortcuts: `packaging/install-desktop.sh` (dconf `local` db).

LocumView uses **Alt** as its shortcut key. On most remote-desktop clients the Windows/Super key is captured by your own computer, but Alt is passed through to LocumView.

## Top-left corner

The **LocumView logo** and the **workspace dots** sit together at the top left.

- **Click** it to open the overview, where you can search for and launch apps and see all open windows.
- The dots show your workspaces. The wide dot is the one you're on.
- **Scroll** over it to move between workspaces.

## Workspaces

Workspaces are separate desktops. You might keep the EHR on one, email on another, and reference material on a third. A new empty workspace appears automatically when you use the last one, and empty ones disappear.

| Shortcut | Action |
|---|---|
| **Alt + 1 … 9, Alt + 0** | Go to workspace 1 … 10 (only workspaces that already exist) |
| **Shift + Alt + 1 … 0** | Move the current window to that workspace |

## Arranging windows

| Shortcut | Action |
|---|---|
| **Alt + I** | Window to the top-left quarter |
| **Alt + O** | Window to the top-right quarter |
| **Alt + K** | Window to the bottom-left quarter |
| **Alt + L** | Window to the bottom-right quarter |

You can also drag a window to a screen edge or corner to snap it there.

## Other shortcuts

| Shortcut | Action |
|---|---|
| **Alt + Enter** | Open a new terminal window |
| **Ctrl + Alt + Q** | Lock the screen. Always lock when you step away. |
| **Alt + Tab** | Switch between open apps |
| **Alt + F4** | Close the current window |

## Things that work differently

- **Switching browser tabs:** Alt + number switches workspaces, so in Firefox use **Ctrl + Tab** / **Ctrl + Shift + Tab** or **Ctrl + Page Up / Page Down**.
- **Office menus:** in ONLYOFFICE, **Alt + I** and **Alt + O** arrange windows instead of opening the Insert and Format menus. Use the mouse, or press **F10** to reach the menus from the keyboard.

## The dock

The dock along the bottom shows your favourite and running apps. Click an app to open or switch to it, and right-click for more options.
