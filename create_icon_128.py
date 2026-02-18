from PIL import Image, ImageDraw, ImageFont

# Create 128x128 icon with the exact design from the provided image
img = Image.new('RGB', (128, 128), color='#FF7259')
draw = ImageDraw.Draw(img)

# Use a good bold font
try:
    font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 72)
except:
    font = ImageFont.load_default()

# Draw "AiFly" text centered
text = "AiFly"
bbox = draw.textbbox((0, 0), text, font=font)
text_width = bbox[2] - bbox[0]
text_height = bbox[3] - bbox[1]

# Center the text
x = (128 - text_width) // 2
y = (128 - text_height) // 2 - 5

# Draw white text
draw.text((x, y), text, fill='white', font=font)

# Save as icon
img.save('icons/icon-128.png')
print("✅ Created 128x128 icon: icons/icon-128.png")
print(f"Size: 128x128 pixels")
print(f"Color: Coral (#FF7259) background with white text")
print(f"Ready for Chrome Web Store")
