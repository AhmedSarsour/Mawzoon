#!/bin/bash
find assets -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.PNG" -o -iname "*.JPG" \) | while read img; do
    echo "Converting $img"
    cwebp -quiet -q 80 "$img" -o "${img%.*}.webp"
    if [ $? -eq 0 ]; then
        rm "$img"
    else
        echo "Failed to convert $img"
    fi
done

# Replace in lib
find lib -type f -name "*.dart" | while read str; do
    sed -i '' -e 's/\.png/.webp/g' -e 's/\.jpg/.webp/g' -e 's/\.jpeg/.webp/g' -e 's/\.PNG/.webp/g' "$str"
done

# Replace in pubspec.yaml if there are direct references (though it usually uses folders)
sed -i '' -e 's/\.png/.webp/g' -e 's/\.jpg/.webp/g' -e 's/\.jpeg/.webp/g' -e 's/\.PNG/.webp/g' pubspec.yaml

