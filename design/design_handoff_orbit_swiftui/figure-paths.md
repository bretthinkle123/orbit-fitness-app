# ORBIT Body-Figure Geometry (source of truth)

Four figures on a 220 x 290 grid (pt). Order below: male front, female front, male back, female back.
The M / W toggle swaps male/female; the back figure stands BELOW the front figure in the scroll
(captions "Front" / "Back"). Both float vertically +/-7pt on a ~6s ease loop, with a soft radial glow
behind (primary at 18-22% alpha, ~210pt circle) and an ellipse ground shadow (baked into each SVG).

## Fill mapping
Each shape's fill is either a muscle token (level color) or the neutral body color.

- Neutral (head, neck, hands, pelvis, knees, feet): rgba(244,240,255,0.13)
- Outline on muscle shapes: 1pt rgba(12,6,26,0.4)
- Muscle tokens -> group (default level, 1-6 on the Beginner->World Class scale):
  mChest  -> Chest (4)      mDelts -> Shoulders (3)   mTraps -> Traps (3)
  mBiceps -> Biceps (3)     mFore  -> Forearms (2)    mCore  -> Core (3)
  mQuads  -> Quads (2)      mCalves-> Calves (1)      mLats  -> Lats (4)
  mTri    -> Triceps (3)    mLow   -> Lower back (3)  mGlutes-> Glutes (2)
  mHams   -> Hamstrings (2)
- Level color = 6-stop scale from the active palette (see README "Strength-level scale").
- "Trained today" glow: shapes whose group received a logged set get
  filter: drop-shadow(0 0 7px secondaryLight @ 85%) - tokens fxChestA / fxDeltsA / fxTriA ('none' otherwise).
- All fills transition 0.4s on change (level recolor, palette switch, M/W crossfade).

SwiftUI: convert each shape to a Path (Q = quadraticCurve, ellipse/rect/circle/polygon as shapes);
fill with Theme.levelColor(group); apply .shadow for the glow.

## Male — FRONT view

```svg
<svg width="220" height="290" viewBox="0 0 220 290">
<ellipse cx="110" cy="282" rx="36" ry="4.5" style="fill:rgba({{ rPri }},.16)"></ellipse>
<circle cx="110" cy="25" r="13.5" style="fill:rgba(244,240,255,.13)"></circle>
<path d="M104,37 Q110,40 116,37 L116,47 Q110,50 104,47 Z" style="fill:rgba(244,240,255,.13)"></path>
<path d="M103,47 Q88,50 79,58 L103,60 Z" style="fill:{{ mTraps }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<path d="M117,47 Q132,50 141,58 L117,60 Z" style="fill:{{ mTraps }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<path d="M63,58 Q72,50 83,55 Q87,64 83,73 Q71,76 64,69 Q61,63 63,58 Z" style="fill:{{ mDelts }};stroke:rgba(12,6,26,.4);stroke-width:1;filter:{{ fxDeltsA }};transition:fill .4s"></path>
<path d="M157,58 Q148,50 137,55 Q133,64 137,73 Q149,76 156,69 Q159,63 157,58 Z" style="fill:{{ mDelts }};stroke:rgba(12,6,26,.4);stroke-width:1;filter:{{ fxDeltsA }};transition:fill .4s"></path>
<path d="M86,58 Q97,53 108,57 L108,79 Q96,86 87,79 Q82,68 86,58 Z" style="fill:{{ mChest }};stroke:rgba(12,6,26,.4);stroke-width:1;filter:{{ fxChestA }};transition:fill .4s"></path>
<path d="M134,58 Q123,53 112,57 L112,79 Q124,86 133,79 Q138,68 134,58 Z" style="fill:{{ mChest }};stroke:rgba(12,6,26,.4);stroke-width:1;filter:{{ fxChestA }};transition:fill .4s"></path>
<path d="M62,80 Q70,76 75,82 Q77,92 74,104 Q70,111 65,108 Q59,96 62,80 Z" style="fill:{{ mBiceps }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<path d="M158,80 Q150,76 145,82 Q143,92 146,104 Q150,111 155,108 Q161,96 158,80 Z" style="fill:{{ mBiceps }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<path d="M52,114 Q58,110 63,115 Q66,126 62,140 Q59,148 54,146 Q49,132 52,114 Z" style="fill:{{ mFore }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<path d="M168,114 Q162,110 157,115 Q154,126 158,140 Q161,148 166,146 Q171,132 168,114 Z" style="fill:{{ mFore }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<circle cx="50" cy="152" r="4.8" style="fill:rgba(244,240,255,.13)"></circle>
<circle cx="170" cy="152" r="4.8" style="fill:rgba(244,240,255,.13)"></circle>
<path d="M88,88 Q93,86 96,90 L96,120 Q93,126 89,122 Q86,105 88,88 Z" style="fill:{{ mCore }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<path d="M132,88 Q127,86 124,90 L124,120 Q127,126 131,122 Q134,105 132,88 Z" style="fill:{{ mCore }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<rect x="99" y="86" width="10" height="11" rx="4" style="fill:{{ mCore }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></rect>
<rect x="111" y="86" width="10" height="11" rx="4" style="fill:{{ mCore }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></rect>
<rect x="99" y="99" width="10" height="11" rx="4" style="fill:{{ mCore }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></rect>
<rect x="111" y="99" width="10" height="11" rx="4" style="fill:{{ mCore }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></rect>
<rect x="99" y="112" width="10" height="11" rx="4" style="fill:{{ mCore }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></rect>
<rect x="111" y="112" width="10" height="11" rx="4" style="fill:{{ mCore }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></rect>
<rect x="99" y="125" width="22" height="9" rx="4.5" style="fill:{{ mCore }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></rect>
<path d="M96,138 L124,138 Q122,153 110,160 Q98,153 96,138 Z" style="fill:rgba(244,240,255,.13)"></path>
<path d="M90,160 Q98,155 106,161 Q109,182 105,204 Q101,212 95,209 Q88,186 90,160 Z" style="fill:{{ mQuads }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<path d="M130,160 Q122,155 114,161 Q111,182 115,204 Q119,212 125,209 Q132,186 130,160 Z" style="fill:{{ mQuads }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<circle cx="99" cy="213" r="4.2" style="fill:rgba(244,240,255,.13)"></circle>
<circle cx="121" cy="213" r="4.2" style="fill:rgba(244,240,255,.13)"></circle>
<path d="M92,222 Q99,216 105,223 Q107,238 102,256 Q98,262 95,258 Q90,240 92,222 Z" style="fill:{{ mCalves }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<path d="M128,222 Q121,216 115,223 Q113,238 118,256 Q122,262 125,258 Q130,240 128,222 Z" style="fill:{{ mCalves }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<rect x="87" y="266" width="18" height="8" rx="4" style="fill:rgba(244,240,255,.13)"></rect>
<rect x="115" y="266" width="18" height="8" rx="4" style="fill:rgba(244,240,255,.13)"></rect>
</svg>
```

## Female — FRONT view

```svg
<svg width="220" height="290" viewBox="0 0 220 290">
<ellipse cx="110" cy="276" rx="32" ry="4" style="fill:rgba({{ rPri }},.16)"></ellipse>
<circle cx="110" cy="9.5" r="4.2" style="fill:rgba(244,240,255,.13)"></circle>
<circle cx="110" cy="24" r="12.5" style="fill:rgba(244,240,255,.13)"></circle>
<path d="M105,35.5 Q110,38 115,35.5 L115,45 Q110,47.5 105,45 Z" style="fill:rgba(244,240,255,.13)"></path>
<path d="M104,45.5 Q92,48 84,54 L104,56 Z" style="fill:{{ mTraps }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<path d="M116,45.5 Q128,48 136,54 L116,56 Z" style="fill:{{ mTraps }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<path d="M70,55 Q78,49 87,53 Q90,60 87,68 Q77,71 71,65 Q68,60 70,55 Z" style="fill:{{ mDelts }};stroke:rgba(12,6,26,.4);stroke-width:1;filter:{{ fxDeltsA }};transition:fill .4s"></path>
<path d="M150,55 Q142,49 133,53 Q130,60 133,68 Q143,71 149,65 Q152,60 150,55 Z" style="fill:{{ mDelts }};stroke:rgba(12,6,26,.4);stroke-width:1;filter:{{ fxDeltsA }};transition:fill .4s"></path>
<ellipse cx="97" cy="71.5" rx="11" ry="10.5" transform="rotate(-8 97 71.5)" style="fill:{{ mChest }};stroke:rgba(12,6,26,.4);stroke-width:1;filter:{{ fxChestA }};transition:fill .4s"></ellipse>
<ellipse cx="123" cy="71.5" rx="11" ry="10.5" transform="rotate(8 123 71.5)" style="fill:{{ mChest }};stroke:rgba(12,6,26,.4);stroke-width:1;filter:{{ fxChestA }};transition:fill .4s"></ellipse>
<path d="M68,76 Q75,72 79,78 Q81,87 78,98 Q74,104 70,101 Q65,89 68,76 Z" style="fill:{{ mBiceps }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<path d="M152,76 Q145,72 141,78 Q139,87 142,98 Q146,104 150,101 Q155,89 152,76 Z" style="fill:{{ mBiceps }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<path d="M59,107 Q64,103 68,108 Q70,118 67,131 Q64,138 60,136 Q56,122 59,107 Z" style="fill:{{ mFore }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<path d="M161,107 Q156,103 152,108 Q150,118 153,131 Q156,138 160,136 Q164,122 161,107 Z" style="fill:{{ mFore }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<circle cx="57" cy="143" r="4.4" style="fill:rgba(244,240,255,.13)"></circle>
<circle cx="163" cy="143" r="4.4" style="fill:rgba(244,240,255,.13)"></circle>
<path d="M90,85 Q94,83 97,87 L97,114 Q94,119 91,116 Q88,100 90,85 Z" style="fill:{{ mCore }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<path d="M130,85 Q126,83 123,87 L123,114 Q126,119 129,116 Q132,100 130,85 Z" style="fill:{{ mCore }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<rect x="100" y="83" width="9.5" height="10" rx="4" style="fill:{{ mCore }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></rect>
<rect x="110.5" y="83" width="9.5" height="10" rx="4" style="fill:{{ mCore }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></rect>
<rect x="100" y="95" width="9.5" height="10" rx="4" style="fill:{{ mCore }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></rect>
<rect x="110.5" y="95" width="9.5" height="10" rx="4" style="fill:{{ mCore }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></rect>
<rect x="100" y="107" width="9.5" height="10" rx="4" style="fill:{{ mCore }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></rect>
<rect x="110.5" y="107" width="9.5" height="10" rx="4" style="fill:{{ mCore }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></rect>
<rect x="100" y="119" width="20" height="8.5" rx="4" style="fill:{{ mCore }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></rect>
<path d="M93,131 L127,131 Q129,150 110,161 Q91,150 93,131 Z" style="fill:rgba(244,240,255,.13)"></path>
<path d="M89,158 Q97,152 106,159 Q109,178 105,199 Q101,207 95,204 Q87,182 89,158 Z" style="fill:{{ mQuads }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<path d="M131,158 Q123,152 114,159 Q111,178 115,199 Q119,207 125,204 Q133,182 131,158 Z" style="fill:{{ mQuads }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<circle cx="99" cy="208" r="4" style="fill:rgba(244,240,255,.13)"></circle>
<circle cx="121" cy="208" r="4" style="fill:rgba(244,240,255,.13)"></circle>
<path d="M92,217 Q98,211 104,218 Q106,232 101,249 Q97,255 94,251 Q89,234 92,217 Z" style="fill:{{ mCalves }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<path d="M128,217 Q122,211 116,218 Q114,232 119,249 Q123,255 126,251 Q131,234 128,217 Z" style="fill:{{ mCalves }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<rect x="88" y="259" width="17" height="8" rx="4" style="fill:rgba(244,240,255,.13)"></rect>
<rect x="115" y="259" width="17" height="8" rx="4" style="fill:rgba(244,240,255,.13)"></rect>
</svg>
```

## Male — BACK view

```svg
<svg width="220" height="290" viewBox="0 0 220 290">
<ellipse cx="110" cy="282" rx="36" ry="4.5" style="fill:rgba({{ rPri }},.16)"></ellipse>
<circle cx="110" cy="25" r="13.5" style="fill:rgba(244,240,255,.13)"></circle>
<path d="M104,37 Q110,40 116,37 L116,45 Q110,48 104,45 Z" style="fill:rgba(244,240,255,.13)"></path>
<path d="M110,44 Q96,48 84,56 Q98,60 104,64 L110,86 L116,64 Q122,60 136,56 Q124,48 110,44 Z" style="fill:{{ mTraps }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<path d="M63,58 Q72,50 83,55 Q87,64 83,73 Q71,76 64,69 Q61,63 63,58 Z" style="fill:{{ mDelts }};stroke:rgba(12,6,26,.4);stroke-width:1;filter:{{ fxDeltsA }};transition:fill .4s"></path>
<path d="M157,58 Q148,50 137,55 Q133,64 137,73 Q149,76 156,69 Q159,63 157,58 Z" style="fill:{{ mDelts }};stroke:rgba(12,6,26,.4);stroke-width:1;filter:{{ fxDeltsA }};transition:fill .4s"></path>
<path d="M84,68 Q95,64 103,70 L103,92 Q99,116 92,124 Q84,100 84,68 Z" style="fill:{{ mLats }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<path d="M136,68 Q125,64 117,70 L117,92 Q121,116 128,124 Q136,100 136,68 Z" style="fill:{{ mLats }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<path d="M62,80 Q70,76 75,82 Q77,92 74,104 Q70,111 65,108 Q59,96 62,80 Z" style="fill:{{ mTri }};stroke:rgba(12,6,26,.4);stroke-width:1;filter:{{ fxTriA }};transition:fill .4s"></path>
<path d="M158,80 Q150,76 145,82 Q143,92 146,104 Q150,111 155,108 Q161,96 158,80 Z" style="fill:{{ mTri }};stroke:rgba(12,6,26,.4);stroke-width:1;filter:{{ fxTriA }};transition:fill .4s"></path>
<path d="M52,114 Q58,110 63,115 Q66,126 62,140 Q59,148 54,146 Q49,132 52,114 Z" style="fill:{{ mFore }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<path d="M168,114 Q162,110 157,115 Q154,126 158,140 Q161,148 166,146 Q171,132 168,114 Z" style="fill:{{ mFore }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<circle cx="50" cy="152" r="4.8" style="fill:rgba(244,240,255,.13)"></circle>
<circle cx="170" cy="152" r="4.8" style="fill:rgba(244,240,255,.13)"></circle>
<rect x="102" y="96" width="7" height="34" rx="3.5" style="fill:{{ mLow }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></rect>
<rect x="111" y="96" width="7" height="34" rx="3.5" style="fill:{{ mLow }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></rect>
<path d="M95,136 Q107,133 108,147 Q108,160 98,162 Q90,155 91,145 Q92,138 95,136 Z" style="fill:{{ mGlutes }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<path d="M125,136 Q113,133 112,147 Q112,160 122,162 Q130,155 129,145 Q128,138 125,136 Z" style="fill:{{ mGlutes }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<path d="M90,166 Q98,161 106,167 Q109,186 105,206 Q101,214 95,211 Q88,190 90,166 Z" style="fill:{{ mHams }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<path d="M130,166 Q122,161 114,167 Q111,186 115,206 Q119,214 125,211 Q132,190 130,166 Z" style="fill:{{ mHams }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<circle cx="99" cy="215" r="4.2" style="fill:rgba(244,240,255,.13)"></circle>
<circle cx="121" cy="215" r="4.2" style="fill:rgba(244,240,255,.13)"></circle>
<path d="M92,222 Q99,216 105,223 Q107,238 102,256 Q98,262 95,258 Q90,240 92,222 Z" style="fill:{{ mCalves }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<path d="M128,222 Q121,216 115,223 Q113,238 118,256 Q122,262 125,258 Q130,240 128,222 Z" style="fill:{{ mCalves }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<rect x="87" y="266" width="18" height="8" rx="4" style="fill:rgba(244,240,255,.13)"></rect>
<rect x="115" y="266" width="18" height="8" rx="4" style="fill:rgba(244,240,255,.13)"></rect>
</svg>
```

## Female — BACK view

```svg
<svg width="220" height="290" viewBox="0 0 220 290">
<ellipse cx="110" cy="276" rx="32" ry="4" style="fill:rgba({{ rPri }},.16)"></ellipse>
<circle cx="110" cy="9.5" r="4.2" style="fill:rgba(244,240,255,.13)"></circle>
<circle cx="110" cy="24" r="12.5" style="fill:rgba(244,240,255,.13)"></circle>
<path d="M105,35.5 Q110,38 115,35.5 L115,43 Q110,45.5 105,43 Z" style="fill:rgba(244,240,255,.13)"></path>
<path d="M110,42 Q99,46 88,52 Q100,56 105,60 L110,78 L115,60 Q120,56 132,52 Q121,46 110,42 Z" style="fill:{{ mTraps }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<path d="M70,55 Q78,49 87,53 Q90,60 87,68 Q77,71 71,65 Q68,60 70,55 Z" style="fill:{{ mDelts }};stroke:rgba(12,6,26,.4);stroke-width:1;filter:{{ fxDeltsA }};transition:fill .4s"></path>
<path d="M150,55 Q142,49 133,53 Q130,60 133,68 Q143,71 149,65 Q152,60 150,55 Z" style="fill:{{ mDelts }};stroke:rgba(12,6,26,.4);stroke-width:1;filter:{{ fxDeltsA }};transition:fill .4s"></path>
<path d="M88,64 Q97,61 104,66 L104,86 Q100,108 94,116 Q87,94 88,64 Z" style="fill:{{ mLats }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<path d="M132,64 Q123,61 116,66 L116,86 Q120,108 126,116 Q133,94 132,64 Z" style="fill:{{ mLats }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<path d="M68,76 Q75,72 79,78 Q81,87 78,98 Q74,104 70,101 Q65,89 68,76 Z" style="fill:{{ mTri }};stroke:rgba(12,6,26,.4);stroke-width:1;filter:{{ fxTriA }};transition:fill .4s"></path>
<path d="M152,76 Q145,72 141,78 Q139,87 142,98 Q146,104 150,101 Q155,89 152,76 Z" style="fill:{{ mTri }};stroke:rgba(12,6,26,.4);stroke-width:1;filter:{{ fxTriA }};transition:fill .4s"></path>
<path d="M59,107 Q64,103 68,108 Q70,118 67,131 Q64,138 60,136 Q56,122 59,107 Z" style="fill:{{ mFore }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<path d="M161,107 Q156,103 152,108 Q150,118 153,131 Q156,138 160,136 Q164,122 161,107 Z" style="fill:{{ mFore }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<circle cx="57" cy="143" r="4.4" style="fill:rgba(244,240,255,.13)"></circle>
<circle cx="163" cy="143" r="4.4" style="fill:rgba(244,240,255,.13)"></circle>
<rect x="103" y="94" width="6.5" height="30" rx="3" style="fill:{{ mLow }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></rect>
<rect x="110.5" y="94" width="6.5" height="30" rx="3" style="fill:{{ mLow }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></rect>
<path d="M93,128 Q107,125 108,139 Q108,153 97,156 Q88,149 89,138 Q90,131 93,128 Z" style="fill:{{ mGlutes }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<path d="M127,128 Q113,125 112,139 Q112,153 123,156 Q132,149 131,138 Q130,131 127,128 Z" style="fill:{{ mGlutes }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<path d="M89,160 Q97,154 106,161 Q109,178 105,198 Q101,206 95,203 Q87,182 89,160 Z" style="fill:{{ mHams }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<path d="M131,160 Q123,154 114,161 Q111,178 115,198 Q119,206 125,203 Q133,182 131,160 Z" style="fill:{{ mHams }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<circle cx="99" cy="206" r="4" style="fill:rgba(244,240,255,.13)"></circle>
<circle cx="121" cy="206" r="4" style="fill:rgba(244,240,255,.13)"></circle>
<path d="M92,217 Q98,211 104,218 Q106,232 101,249 Q97,255 94,251 Q89,234 92,217 Z" style="fill:{{ mCalves }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<path d="M128,217 Q122,211 116,218 Q114,232 119,249 Q123,255 126,251 Q131,234 128,217 Z" style="fill:{{ mCalves }};stroke:rgba(12,6,26,.4);stroke-width:1;transition:fill .4s"></path>
<rect x="88" y="259" width="17" height="8" rx="4" style="fill:rgba(244,240,255,.13)"></rect>
<rect x="115" y="259" width="17" height="8" rx="4" style="fill:rgba(244,240,255,.13)"></rect>
</svg>
```
