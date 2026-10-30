# altstreamer
AltStream integration for Godot

Based on the AltStream integration for [SnekStudio](https://github.com/ExpiredPopsicle/SnekStudio) by [copygirl](https://github.com/copygirl)

Currently can listen to chat messages, chat clears, chat deletions, chat pins, highlights, rewards, shoutouts, and raids (both incoming and outgoing).

Can not currently control / trigger / send anything on AltStream, this is currently only a listener.

To use: clone the repository and put the entire folder in your Godot project's "addons" folder (if one does not exist, create it: res://addons/) and enable the plugin from your Project Settings.

Then add a "AltStreamService" node to one of your scenes. You can set the channel it listens to in the inspector, as well as set if it connects automatically on start-up. Then connect its' signals to whatever you like.
