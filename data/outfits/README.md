# Complete outfits

Add OutfitData `.tres` resources here with unique, stable `outfit_id` values.
The catalog resolves these IDs for saves. An empty or unavailable ID uses the
existing appearance art. No placeholder clothing is drawn over that art.

Assets still needed: transparent complete-outfit atlases for each body template,
including shoes, hats, backpacks and accessories. Supply matching unclothed base
art where existing baked-in clothing should be replaced.

`frame_regions` maps animation names (`idle_down`, `walk_down_right`, etc.) to
arrays of Rect2 atlas regions. Idle has one pose; walk has five, in the same order
as PlayerSpriteFrames. All eight directions need their own entries. Use one
atlas containing both cardinal and diagonal art. Regions are centered and aligned
at the feet within `frame_size` (208 x 336 by default); transparent padding must
register the clothing to the matching base pose. Missing frames hide the outfit,
never substitute another pose. Swim/dive clothing is deferred.

Call `equip_player_outfit(resource)` or `equip_player_outfit(null)` to equip or
clear an outfit. Incompatible body templates are rejected. Equipped IDs persist
in saves; there is no wardrobe, purchasing or ownership UI in this checkpoint.
Icon is optional, category and price are metadata, and visibility_masks optionally maps animation names to arrays of full-canvas
Texture2D masks, indexed by the same pose index. Mask alpha removes base pixels
only (opaque hides, transparent preserves); clothing itself is unaffected.
Missing masks use ordinary compositing. Foreground hair layering is deferred
until matching outfit art can be tested against the female long-hair presets. Resources are treated as immutable during
play; call clear_frame_cache() after editing atlas regions at runtime.
