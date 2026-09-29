# Implements §9.1 and §9.7 Object pooling.
class_name Pool
extends RefCounted

var _items: Array = []
var _capacity: int = 0
var _factory: Callable

func _init(capacity: int, factory: Callable) -> void:
	_capacity = capacity
	_factory = factory
	for i in range(capacity):
		_items.append(factory.call())

func acquire():
	if _items.is_empty():
		return null
	return _items.pop_back()

func release(item) -> void:
	if item != null and _items.size() < _capacity:
		_items.append(item)

func available_count() -> int:
	return _items.size()

func capacity() -> int:
	return _capacity
