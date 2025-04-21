---------------------------------------------
-- Final Fantasy V Multi-Chaos
---------------------------------------------

This is a small and simple project to allow multiple people to play one
instance of Final Fantasy V at the same time, with some restrictions.

Host Requirements:
- Windows PC
- Bizhawk 2.8 (2.9+ will not work)
- SNES ROM of Final Fintasy V
- (possibly) port forwarding capability
- (currently) A method of streaming Bizhawk with low latency (such as discord)
- server scripts (ff5_multi_chaos.lua and socket.lua)

Player Requirements:
- Windows PC
- Client program

---------------------------------------------

Host Setup:

First, open Bizhawk and the Final Fantasy V ROM. Next, open the Lua console
under Tools. Then navigate to the server folder in the provided files and
open the ff5_multi_chaos.lua script. Under the Config menu, select Customize...
and open the Advanced tab. Make sure the selected Lua Core is Lua+LuaInterface.

A window with several controls should pop up. Enter a value between 1 and 
65535 in the Server Port field and (optionally) choose a password that players
will need to enter in order to connect. Depending on your network, you may
need to setup port forwarding for the port number you entered. This is typically
done in your modem/router configuration. If it asks for type(s) of traffic to
forward, be sure TCP is included. Next, the players will need the host's public IP
address to connect to. If you're not sure what your IP address is, many online
services will tell you, such as https://whatismyipaddress.com/

Finally, click the Start Server button. Players will be able to connect now.
When players are connected, the host will most likely want to stream a video
of the game. The easiest way to accomplish this is with a discord stream, since 
they have fairly low latency. If the host wants to participate in the game, they 
will also need to setup the client.

Whenever a player connects one of the four buttons will populate with their player
and character name. Clicking the button will forcefully disconnect that player.

Below the buttons is a checkbox labeled "Fewer Battles". When checked the
party will be much less likely to get into random battles. This can be useful
for speeding the game along if needed. Below that is the "Show Input" checkbox,
which displays in the top right which buttons each player is currently pressing.

The last button, "Send Video", is currently disabled on both server and client
until stability issues are addressed. When enabled, this will stream a crude video
with low latency directly to each client, allowing for players to see what's 
happening without relying on a separate service.

Beside the buttons are the point counts. Each time players enter battle, they're
awarded one point (or GregBux) that can be used to purchase effects in the shop.
These effects are listed in the file effects.lua. Hosts can customize which affects
are available and how many points each costs by editing this file.

---------------------------------------------

Client Setup:

The client is a standalone Windows executable. Enter the IP address, port and
password supplied to you by the host in the appropriate fields, choose a player
name of up to 6 characters (only numbers and English letters are valid), and
(optionally) choose which character you would prefer to play as.

Once all the info is entered, click the Connect button. If the connection is
successful and there is a free player slot, you'll see which character you've
been assigned, as well as if you currently have control in the game.

If you haven't yet, open the host's stream of the game so you can see what's
happening.

At any point during gameplay you can change your player name. Remember to click
"Update Player Name" after you've entered it. Note that if the character you've
been assigned leaves the party, their name will be reset when they re-join.

Three methods of input are supported: keyboard, gamepad and mouse.
When first loading the client, a mapping of keyboard keys to SNES inputs is shown.
Most modern gamepads will be detected and will use a control scheme that roughly
matches the SNES controller. Finally, the buttons for each of the SNES inputs can be
clicked to send that input as long as the button is depressed.

Since the client will read inputs even if the window isn't focused, it will pick up
key presses when you might not intend. If you need to type elsewhere using your keyboard,
the Disable Input button in the bottom left will prevent any input from going through
while it's checked.

---------------------------------------------

Control Logic:

Each player loses and gains control at certain times. Outside of battle all players are
in control. In battle control is a little more complex.

- If the player's character's turn is active, they gain control
- If there is no player for a character (e.g. there are 3 players and no one is assigned
  to Faris), then all players have control.
- If a player takes too long to finish their turn (20 seconds currently), then all players
  gain control for that turn.
  
---------------------------------------------
