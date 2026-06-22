# Swifly

> Instant WiFi file transfer — phone to PC, no install, no cloud.

Open the site on your PC, scan the QR with your phone, pick a file. Done.

## How it works

- Both devices open the same URL in their browser
- The PC generates a unique pairing code and QR code
- The phone scans the QR code (or types the code into its browser)
- A direct **WebRTC peer-to-peer** connection is established
- The file transfers directly — **no server, no cloud, no upload**

## Requirements

- Both devices on the **same WiFi network**
- A modern browser (Chrome, Safari, Edge, Firefox)
- No app install needed on either device

## Deploy to Vercel

[![Deploy with Vercel](https://vercel.com/button)](https://vercel.com/new)

```bash
npx vercel --prod
```

Or drag the folder into [vercel.com/new](https://vercel.com/new).

## Local Preview

```bash
python -m http.server 8080
```

Then open [http://localhost:8080](http://localhost:8080).

## Tech Stack

- Plain HTML + Vanilla JS (zero build step)
- [PeerJS](https://peerjs.com/) for WebRTC signaling
- Deployable as a static site on Vercel, Netlify, GitHub Pages, etc.
