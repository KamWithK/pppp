# Pixel Perfect Painted Pipeline

> [!NOTE]
> Me learning graphics programming, and exploring learning about gamedev.

You spent your life drawing paintings, but today is the day you will breath new life into them.
A change in scenery and a change in approach is your one last hope.
To bring the beauty and serenity of your paintings to life, you've decided to adopt the island life, the factory island life...
Hone your craft and spread it with the rest of the world.
Today you will plan process n' place, puzzle painting pieces perfectly.

Build a factory pipeline to manufacture puzzle pieces, and assemble them into the real thing!
Start with red, green and blue pixels, and set up machinery to mix colours, combine or scramble pieces.
When exceed goals you get bonuses, these are symbolised with small decorations to place around the map.

If you ship an incorrect item your satisfaction will go down, and the box will be sent back to be recycled.
If the item is fixed then the satisfaction resets back.
The bigger puzzles are significantly more impressive and will expand your audience to more dedicated puzzlers.

On an island, below you is the sea and boats come into port regularly, loading their pixel block cargo into marine depots.
To light up the map place items like fireplaces.

Before starting to place down machinery, place wood onto the ground, this will show the world grid visually.
Maybe tiles of a few different patterns can be alternated between to form patterns.

Surrounding smaller factories with rivers or trees will increase their efficiency as it prevents contamination.

## Technical Design

### Chunks

Chunks are small regions of the map which can be loaded all at once.
Chunks ensure all entities in an area are loaded and freed at once.

Only the chunks on screen need to be rendered.
But, all chunks in the factory need to be ticked, so items accrue.

Chunks along with everything within them must be versioned with a generation.

Everything within the chunk should be stored with a Morton or Hilbert curve sorted index.

### Belts

Belts are the medium of transport within the factory.
Belts are built in segments, which have several properties:

- Segments chain when connected, allowing 90 degree turns.
- Items move from source to sink, in this segment and any connected in a chain.
- Segments without a source or sink do nothing.
- Segments are placed in a horizontal or vertical orientation.
- Segments have a positive or negative direction.
- Segments should be extended if they have the same orientation and direction.

Belt only function once connected to a machine, as it will be implemented pull based.
Each segment should be rendered in one draw call.

Each segment is represented by:

- Type.
- Start position.
- End position.
- First tile offset from start.
- Last tile offset from end.
- Speed per tick.
- Start time.

### Machines

Machines have no inventory, they instead have one or more sources and sinks.

Basic machines include:

- Rotators which rotate tiles by 90 degrees.
- Combiners which combine two or more tiles.

### Items

Items like tiles are processed by belts and machines.
