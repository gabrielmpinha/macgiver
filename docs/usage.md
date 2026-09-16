# Usage and troubleshooting

[Documentation index](README.md) · [Build and verification](development.md)

## Open the panel

Launch MacGiver, then click its menu bar icon. The app runs without a Dock icon or a standalone window.

The panel opens with a compact battery summary and three utility switches. Click the battery summary to expand details within the same panel. Use the upward chevron to collapse them. Closing and reopening the panel returns it to the compact layout.

The menu bar symbol changes when Keep Awake or Lock Keyboard is active; the keyboard-lock symbol takes priority when both are enabled.

## Language

MacGiver includes complete English, Portuguese, and Spanish translations. It uses the first supported language in your macOS preferred-language list, falling back to English when none is supported. Regional language preferences such as Portuguese (Brazil), Portuguese (Portugal), and Spanish (Mexico) use the corresponding Portuguese or Spanish translation.

To choose a different language just for MacGiver, open **System Settings > General > Language & Region > Applications** and add MacGiver with your preferred language. Quit and reopen the app after changing it. Numbers and chart times follow your regional formatting preferences, which can differ from the interface language.

The instructions in this guide use the English control names. The app name **MacGiver** remains the same in every language.

## Keep Awake

Enable **Keep Awake** to prevent idle system sleep. Disable it to release the sleep-prevention request. Quitting the app also ends that request.

This feature does not request display-sleep prevention, override an explicit Sleep command, or implement closed-lid operation. It starts disabled when the app launches.

## Lock Keyboard

Enable **Lock Keyboard** before cleaning your keys. On first use:

1. Open **System Settings > Privacy & Security > Accessibility**.
2. Enable MacGiver.
3. Return to MacGiver and enable **Lock Keyboard** again.

The app intercepts key-down, key-up, and modifier-change events in the current user session. The lock is not restricted to the built-in keyboard. Mouse and trackpad input remain available so you can reopen the panel and disable the switch.

This is a cleaning utility, not a security or screen lock. It starts disabled when the app launches.

## Keyboard Light

**Keyboard Light** controls the built-in keyboard backlight:

- Turning it off saves the current brightness for this app session.
- Turning it back on restores that saved value.
- If the keyboard starts dark and there is no saved value, turning it on uses 50% brightness.
- While the panel is open, the switch refreshes once a second to follow external brightness changes.

A change is confirmed by reading brightness back from the hardware. If brightness cannot be read, the switch is disabled and **Retry Keyboard Light** is available. An unconfirmed write displays an error and refreshes the observed state.

The saved brightness is not persisted across launches. Quitting does not explicitly restore brightness. Automatic-brightness and idle-dimming preferences are not changed, although a manual brightness override can take precedence over automatic adjustment.

Backlight control depends on the private CoreBrightness framework. Availability can change with macOS or hardware, and external keyboard lighting is not controlled.

## Mac battery

Expand the battery summary to see:

| Reading | Meaning |
| --- | --- |
| Charge | Current battery percentage. |
| State | On battery, charging, fully charged, or plugged in without charging. |
| Time remaining / Until full | The estimate supplied by macOS; **Estimating…** means no usable estimate is available. |
| Battery power | Watts entering or leaving the battery. Positive means discharge; negative means charging. |
| Health | Estimated capacity relative to the battery's design capacity. |
| Cycles | Reported total battery cycle count. |

Battery power is not total computer or wall-outlet power. A connected charger does not by itself determine whether the battery is charging or discharging.

Health is calculated from available nominal/raw capacity values and may differ from System Settings. Unavailable fields appear as a dash or an unavailable state rather than a fabricated zero.

### Energy history

Select **15m**, **1h**, or **6h** and hover over a chart to inspect a reading.

Mac battery data is sampled every five seconds while the app is running, including when the panel is closed. History begins at launch, retains up to six hours in memory, and is cleared on quit. Sleep/wake transitions, long sampling gaps, and missing measurements break the chart line.

## Permissions and data

Accessibility access is used to intercept keyboard events for Lock Keyboard. The current implementation drops those events rather than recording their contents.

Mac battery readings come from local macOS interfaces. There is no application account, analytics service, or network backend in the current source. Battery history stays in memory; it is not exported or saved between launches.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| No app window or Dock icon | Open MacGiver from its menu bar icon. This is the intended interface. |
| Lock Keyboard will not enable | Grant Accessibility permission, then try the switch again. If macOS still rejects the event tap, relaunch and retry. |
| Keyboard brightness is unavailable | Confirm the Mac has a built-in backlit keyboard, then click **Retry Keyboard Light**. The private interface may be unavailable on that system. |
| Keep Awake allows the display to turn off | It prevents idle system sleep, not display sleep. |
| Time remaining says **Estimating…** | macOS has not supplied a usable estimate. MacGiver does not invent one. |
| History is empty after launch | Samples accumulate during the current run. The chart shows a point immediately and a line after the next five-second sample; previous sessions are not retained. |

For build or signing failures, see [development troubleshooting](development.md#build-troubleshooting).
