extends SGCharacterBody2D
class_name BaseCharacter

@export var debug: bool

@export var charData: CharacterData

@export_category("Physics")
@export var gravity: int = 10
@onready var floor_detection: SGArea2D = $AreasParent/FloorDetection
@onready var main_collision: SGCollisionShape2D = $MainCollision
@export_category("Frame Data")
@export var frameData: HitFrameData
@export var hitboxes: Array[SGArea2D]
@export var hurtBoxes : Array[SGArea2D]
@export_category("Graphics")
@onready var sprite_2d: Sprite2D = $Sprite2D
@onready var anim_player: AnimationPlayer = $AnimPlayer

var currentHP: int
var currentJump: int
var currentBack: int
var onFloor: bool = true
var crouching: bool = false

# STATES ##########################################
enum charStates {idle, movingForward, movingBack, jumping, crouching, attacking, takingDamage, blockStunned, hitStunned, throwed, juggled, knockedDown}
var stateTick: int = 0
var currentState: charStates
var currentAttackData: AttackData

# ANIMATION ##########################################
var currentAnim: String
var animTick: int = 0
var animLength: int = 0
var looping:bool = false
var animBlocked: bool = false

# CONTROLLER ##########################################
var prefix: String = "P1_"
const KEY_WALK: String = "walk"
const KEY_JUMP: String = "jump"
const KEY_CROUCH: String = "crouch"
const KEY_PUNCH: String = "punch"
const KEY_KICK: String = "kick"
const KEY_SPECIAL_A: String = "specialA"
const KEY_SPECIAL_B: String = "specialB"

const FIXED: int = 65536

func _ready() -> void:
	currentHP = charData.maxHP
	fixed_position_x = int(position.x * FIXED)
	fixed_position_y = int(position.y * FIXED)
	SetIdle()

func _save_state() -> Dictionary:
	return {
		fixed_position_x = fixed_position_x,
		fixed_position_y = fixed_position_y,
		currentJump = currentJump,
		currentHP = currentHP,
		currentBack = currentBack,
		onFloor = onFloor,
		stateTick = stateTick,
		looping = looping,
		animLength = animLength,
		animBlocked = animBlocked
	}

func _load_state(state: Dictionary) -> void:
	fixed_position_x = state["fixed_position_x"]
	fixed_position_y = state["fixed_position_y"]
	currentJump = state["currentJump"]
	currentHP = state["currentHP"]
	currentBack = state["currentBack"]
	onFloor = state["onFloor"]
	stateTick = state["stateTick"]
	looping = state["looping"]
	animLength = state["animLength"]
	animBlocked = state["animBlocked"]
	sync_to_physics_engine()
	floor_detection.sync_to_physics_engine()

func _get_local_input() -> Dictionary:
	var inputs: Dictionary = {}
	
	var movement: int = 0
	if Input.is_action_pressed(prefix+"left"):
		movement = -1
	elif Input.is_action_pressed(prefix+"right"):
		movement = 1
	
	if movement != 0: #ADD MOVEMENT
		inputs[KEY_WALK] = movement
	
	if Input.is_action_just_pressed(prefix+"up"): #ADD JUMP
		inputs[KEY_JUMP] = true
	
	if Input.is_action_pressed(prefix+"down"): #ADD CROUCH
		inputs[KEY_CROUCH] = true
	
	if Input.is_action_just_pressed(prefix+"punch"): #ADD PUNCH
		inputs[KEY_PUNCH] = true
	
	if Input.is_action_just_pressed(prefix+"kick"): #ADD KICK
		inputs[KEY_KICK] = true
	
	return inputs

func _predict_remote_input(previous_input: Dictionary, _ticks_since_real_input: int) -> Dictionary:
	var inputs = previous_input.duplicate()
	inputs.erase(KEY_JUMP)
	inputs.erase(KEY_PUNCH)
	inputs.erase(KEY_KICK)
	return inputs

func _network_process(input: Dictionary) -> void:
	sync_to_physics_engine()
	
	var movement = input.get(KEY_WALK, 0)
	
	if input.get(KEY_JUMP, false) && onFloor:
		Jump()
	
	if input.get(KEY_CROUCH, false) && onFloor:
		crouching = true
	else:
		crouching = false
	
	if input.get(KEY_PUNCH, false):
		Attack(0)
	
	
	CheckFloor()
	Movement(movement)
	Crouch()
	StateUpdate()
	SetHitboxes()
	
	if input.is_empty():
		CheckIdle()
	
	pass

func CheckFloor() -> void:
	floor_detection.sync_to_physics_engine()
	if floor_detection.get_overlapping_body_count() > 0 && currentJump <= 0:
		onFloor = true
	else:
		onFloor = false
	pass

func Movement(movement: int) -> void:
	if !crouching:
		if !onFloor:
			currentJump -= gravity
		velocity = SGFixed.vector2(movement * charData.moveSpeed * FIXED, -currentJump * FIXED)
		move_and_slide()
		
		if movement != 0 && onFloor:
			if movement != currentBack:
				SetState(charStates.movingForward, 0)
			else:
				SetState(charStates.movingBack, 1)
	pass

func Crouch() -> void:
	if crouching:
		SetState(charStates.crouching, 0)
	pass

func Jump() -> void:
	onFloor = false
	currentJump = charData.maxJump
	SetState(charStates.jumping, 0)
	pass

func Attack(id: int) -> void:
	SetState(charStates.attacking, id)
	pass

func Flip(newBack: int) -> void:
	if newBack == 1:
		sprite_2d.flip_h = true
	else:
		sprite_2d.flip_h = false
	
	currentBack = newBack
	pass

# STATES ##################################################################################
func SetState(newState: charStates, aux: int) -> void:
	if newState != currentState && !animBlocked:
		stateTick = 0
		if newState == charStates.idle:
			SetIdle()
		elif newState == charStates.movingForward || newState == charStates.movingBack:
			SetMoving(aux)
		elif newState == charStates.jumping:
			SetJumping()
		elif newState == charStates.crouching:
			SetCrouching()
		elif newState == charStates.attacking:
			SetAttacking(aux)
	pass

func StateUpdate() -> void:
	animTick = stateTick
	stateTick += 1
	if stateTick > animLength:
		if looping:
			stateTick = 0
		else:
			stateTick = animLength
			animBlocked = false
	pass

func SetIdle() -> void:
	currentAttackData = frameData.standData
	currentState = charStates.idle
	SetAnimation("idle", true, false)
	animLength = frameData.idleDuration
	pass

func SetMoving(isForward: int) -> void:
	currentAttackData = frameData.standData
	if isForward == 0:
		SetAnimation("walkForward", true, false)
		currentState = charStates.movingForward
	elif isForward == 1:
		SetAnimation("walkBackwards", true, false)
		currentState = charStates.movingBack
	
	animLength = frameData.standData.duration
	pass

func SetJumping() -> void:
	currentAttackData = frameData.jumpData
	currentState = charStates.jumping
	SetAnimation("jumpStart", true, false)
	animLength = frameData.jumpData.duration
	pass

func SetCrouching() -> void:
	currentAttackData = frameData.crouchData
	currentState = charStates.crouching
	animLength = frameData.crouchData.duration
	SetAnimation("crouch", true, false)
	pass

func SetAttacking(AttackID: int) -> void:
	if AttackID == 0:
		if currentState == charStates.crouching:
			pass #PLAY CROUCHED PUNCH
		elif currentState == charStates.jumping:
			pass #PLAY JUMP PUNCH
		else:
			currentAttackData = frameData.punchData
			animLength = frameData.punchData.duration
			SetAnimation("punch", false, true)
	currentState = charStates.attacking
	pass

func CheckIdle() -> void:
	if !animBlocked && !crouching && onFloor && currentAnim != "idle":
		SetState(charStates.idle, 0)
	pass

func SetAnimation(newAnim: String, newLoop: bool, newBlock: bool) -> void:
	#if currentAnim != newAnim:
	currentAnim = newAnim
	looping = newLoop
	animBlocked = newBlock

func _process(_delta: float) -> void:
	anim_player.play(currentAnim)
	anim_player.seek(float(animTick)/60.0)
	anim_player.advance(0)
	pass

func SetHitboxes() -> void:
	if currentAttackData == null:
		return
	
	for i in hitboxes.size():
		hitboxes[i].fixed_position_x = currentAttackData.hitBox[i]["x"]
		hitboxes[i].fixed_position_y = currentAttackData.hitBox[i]["y"]
		hitboxes[i].fixed_scale_x = currentAttackData.hitBox[i]["w"]
		hitboxes[i].fixed_scale_y = currentAttackData.hitBox[i]["h"]
		
		var shape: SGCollisionShape2D = hitboxes[i].get_child(0)
		if stateTick >= currentAttackData.frameData["active"] && stateTick < currentAttackData.frameData["recovery"]:
			shape.disabled = false
		else:
			shape.disabled = true
		
	for i in hurtBoxes.size():
		hurtBoxes[i].fixed_position_x = currentAttackData.hurtbox[i]["x"]
		hurtBoxes[i].fixed_position_y = currentAttackData.hurtbox[i]["y"]
		hurtBoxes[i].fixed_scale_x = currentAttackData.hurtbox[i]["w"]
		hurtBoxes[i].fixed_scale_y = currentAttackData.hurtbox[i]["h"]
	
		var shape: SGCollisionShape2D = hurtBoxes[i].get_child(0)
		if currentAttackData.frameData["invincible"] != 0 && stateTick >= currentAttackData.frameData["invincible"] && stateTick < currentAttackData.frameData["active"]:
			shape.disabled = true
		else:
			shape.disabled = false
	pass
