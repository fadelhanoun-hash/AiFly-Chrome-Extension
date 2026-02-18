#!/usr/bin/env python3
from PIL import Image, ImageDraw, ImageFont
import os

icon_dir = os.path.join(os.path.dirname(__file__), 'icons')
sizes = [16, 48, 128]

# Use a simple color scheme matching the provided image
bg_color = '#FF7259'  # Coral/salmon color
text_color = 'white'

for size in sizes:
    img = Image.new('RGB', (size, size), color=bg_color)
    draw = ImageDraw.Draw(img)
    
    # Use default font since custom font loading has issues
    font = ImageFont.load_default()
    
    text = 'AiFly' if size >= 48 else 'A'
    
    # For tiny icon, just use one letter
    if size < 32:
        text = 'A'
    
    try:
        bbox = draw.textbbox((0, 0), text, font=font)
        text_width = bbox[2] - bbox[0]
        text_height = bbox[3] - bbox[1]
        x = (size - text_width) // 2
        y = (size - text_height) // 2
    except:
        # Fallback positioning
        x = size // 4
        y = size // 4
    
    draw.text((x, y), text, fill=text_color, font=font)
    filepath = os.path.join(icon_dir, f'icon-{size}.png')
    img.save(filepath)
    print(f'Created {filepath}')

print('All icons created successfully!')

