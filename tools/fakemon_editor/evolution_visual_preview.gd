class_name EvolutionVisualPreview
extends Control

var old_art:TextureRect
var new_art:TextureRect
var caption:Label
var running:=false

func _ready()->void:
	custom_minimum_size=Vector2(900,470)
	var bg:=ColorRect.new();bg.color=Color.BLACK;bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(bg)
	caption=Label.new();caption.position=Vector2(60,28);caption.size=Vector2(780,60);caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;caption.add_theme_font_size_override("font_size",24);add_child(caption)
	old_art=_art();new_art=_art();add_child(old_art);add_child(new_art)

func play(from_name:String,to_name:String,from_image:Image,to_image:Image)->void:
	if running:return
	running=true;old_art.texture=ImageTexture.create_from_image(from_image) if from_image!=null else null;new_art.texture=ImageTexture.create_from_image(to_image) if to_image!=null else null
	caption.text="%s is evolving into %s!"%[from_name,to_name];old_art.modulate.a=1;new_art.modulate.a=0
	var tween:=create_tween();tween.tween_property(old_art,"modulate:a",0.0,1.0);tween.parallel().tween_property(new_art,"modulate:a",1.0,1.0);await tween.finished
	await get_tree().create_timer(0.65).timeout;caption.text="Congratulations! %s evolved into %s!"%[from_name,to_name]
	await get_tree().create_timer(0.9).timeout;running=false
func _art()->TextureRect:
	var art:=TextureRect.new();art.position=Vector2(300,100);art.size=Vector2(300,300);art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;return art
