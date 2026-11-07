<!-- Generated from Sources/AlloyCore/Guides/Guides.swift by `alloyctl write-docs docs`. Edit that file instead. -->

# Graphics Guide

Most games run well with Alloy's defaults. If a game feels slow or looks wrong, go through these steps in order and stop when it plays the way you like.

## Step 1: Start with Balanced

Every game starts in **Balanced**: it runs as smoothly as your display allows, up to its refresh rate, and Alloy paces the frames evenly. Play for a few minutes first. Most games need nothing else.

The first minutes of a new game can stutter while it prepares its shaders. That gets better as you play and is faster on the next start.

## Step 2: Plug in and play in fullscreen

Plug your Mac in and turn off Low Power Mode: on battery, macOS can slow the graphics down.

Play in fullscreen. macOS then turns on Game Mode, which gives the game priority over other apps.

## Step 3: Lower the heavy settings in the game

Open the game's own graphics settings. Shadows, volumetric fog and clouds, ambient occlusion, motion blur and ray tracing cost the most. Lower these first; textures can usually stay high on Macs with 16 GB of memory or more.

If the game has its own frame-rate limit, set it to Unlimited or to your display's rate. Alloy already limits the game to what your display can show.

## Step 4: Still slow? Lower the resolution and choose Sharp

The biggest gain comes from a lower resolution. In the game, choose about half your screen's resolution (for example 1512 × 982 on a 14-inch MacBook Pro), then choose **Sharp** in Alloy. Apple's MetalFX scales the picture back up to your full Retina resolution, so it stays crisp instead of blurry.

In Alloy's GPU test, rendering at 1200 × 778 and scaling up with MetalFX ran at 137 to 172 FPS, against 91 FPS at full resolution. Sharp on its own, at full resolution, costs about 2 milliseconds per frame, so use it together with a lower resolution.

If the game offers DLSS, you can try that instead: with **MetalFX scaling** on (the default in Balanced and Battery Saver), Alloy passes DLSS to Apple's MetalFX. Choosing Sharp turns MetalFX scaling off, so the picture is never upscaled twice.

## Step 5: On battery, choose Battery Saver

**Battery Saver** limits the game to 60 FPS. The Mac stays cooler and quieter and the battery lasts longer. Most single-player games still feel smooth at 60.

It appears on Macs whose display runs faster than 60 Hz. On a 60 Hz display, Balanced already runs at 60.

## Step 6: If the game won't start or looks wrong

First check the game page: Alloy lists problems it found, often with a one-click fix such as installing a missing Windows component.

For a black screen, missing textures or a crash at start, turn on **Compatibility mode**. It switches to a slower, older renderer that some games need. Turn it off again if it doesn't help.
