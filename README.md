# TOG TK Tracker
(togtktracker)

Tracks team kills (TKs) in a database and provides natives and forwards to interact with other plugins. Notifies admins of connecting players with TK counts above a configurable threshold (can be disabled).


## Installation:
* Put togtktracker.smx in the following folder: /addons/sourcemod/plugins/


## CVars:
<details><summary>Click to View CVars</summary>
<p>

* **ttkt_version** - TOG Insurgency Stats: Version

* **ttkt_dbname** - Name of the main database setup for the plugin.

* **ttkt_notifycnt** - Admins are notified if a connecting player has at least this number of TKs on record. Set to 0 to disable notification.

* **ttkt_adminflag** - Players with this flag will be notified when a connecting player has a TK count above ttkt_notifycnt.
</p>
</details>

Note: After changing the cvars in your cfg file, be sure to rcon the new values to the server so that they take effect immediately.





### Check out my plugin list: http://www.togcoding.com/togcoding/index.php
