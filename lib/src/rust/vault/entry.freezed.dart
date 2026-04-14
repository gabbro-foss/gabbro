// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'entry.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$VaultEntry {

 Object get field0;



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VaultEntry&&const DeepCollectionEquality().equals(other.field0, field0));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(field0));

@override
String toString() {
  return 'VaultEntry(field0: $field0)';
}


}

/// @nodoc
class $VaultEntryCopyWith<$Res>  {
$VaultEntryCopyWith(VaultEntry _, $Res Function(VaultEntry) __);
}


/// Adds pattern-matching-related methods to [VaultEntry].
extension VaultEntryPatterns on VaultEntry {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( VaultEntry_Login value)?  login,TResult Function( VaultEntry_Note value)?  note,TResult Function( VaultEntry_Identity value)?  identity,TResult Function( VaultEntry_Card value)?  card,TResult Function( VaultEntry_File value)?  file,TResult Function( VaultEntry_Custom value)?  custom,required TResult orElse(),}){
final _that = this;
switch (_that) {
case VaultEntry_Login() when login != null:
return login(_that);case VaultEntry_Note() when note != null:
return note(_that);case VaultEntry_Identity() when identity != null:
return identity(_that);case VaultEntry_Card() when card != null:
return card(_that);case VaultEntry_File() when file != null:
return file(_that);case VaultEntry_Custom() when custom != null:
return custom(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( VaultEntry_Login value)  login,required TResult Function( VaultEntry_Note value)  note,required TResult Function( VaultEntry_Identity value)  identity,required TResult Function( VaultEntry_Card value)  card,required TResult Function( VaultEntry_File value)  file,required TResult Function( VaultEntry_Custom value)  custom,}){
final _that = this;
switch (_that) {
case VaultEntry_Login():
return login(_that);case VaultEntry_Note():
return note(_that);case VaultEntry_Identity():
return identity(_that);case VaultEntry_Card():
return card(_that);case VaultEntry_File():
return file(_that);case VaultEntry_Custom():
return custom(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( VaultEntry_Login value)?  login,TResult? Function( VaultEntry_Note value)?  note,TResult? Function( VaultEntry_Identity value)?  identity,TResult? Function( VaultEntry_Card value)?  card,TResult? Function( VaultEntry_File value)?  file,TResult? Function( VaultEntry_Custom value)?  custom,}){
final _that = this;
switch (_that) {
case VaultEntry_Login() when login != null:
return login(_that);case VaultEntry_Note() when note != null:
return note(_that);case VaultEntry_Identity() when identity != null:
return identity(_that);case VaultEntry_Card() when card != null:
return card(_that);case VaultEntry_File() when file != null:
return file(_that);case VaultEntry_Custom() when custom != null:
return custom(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( LoginEntry field0)?  login,TResult Function( NoteEntry field0)?  note,TResult Function( IdentityEntry field0)?  identity,TResult Function( CardEntry field0)?  card,TResult Function( FileEntry field0)?  file,TResult Function( CustomEntry field0)?  custom,required TResult orElse(),}) {final _that = this;
switch (_that) {
case VaultEntry_Login() when login != null:
return login(_that.field0);case VaultEntry_Note() when note != null:
return note(_that.field0);case VaultEntry_Identity() when identity != null:
return identity(_that.field0);case VaultEntry_Card() when card != null:
return card(_that.field0);case VaultEntry_File() when file != null:
return file(_that.field0);case VaultEntry_Custom() when custom != null:
return custom(_that.field0);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( LoginEntry field0)  login,required TResult Function( NoteEntry field0)  note,required TResult Function( IdentityEntry field0)  identity,required TResult Function( CardEntry field0)  card,required TResult Function( FileEntry field0)  file,required TResult Function( CustomEntry field0)  custom,}) {final _that = this;
switch (_that) {
case VaultEntry_Login():
return login(_that.field0);case VaultEntry_Note():
return note(_that.field0);case VaultEntry_Identity():
return identity(_that.field0);case VaultEntry_Card():
return card(_that.field0);case VaultEntry_File():
return file(_that.field0);case VaultEntry_Custom():
return custom(_that.field0);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( LoginEntry field0)?  login,TResult? Function( NoteEntry field0)?  note,TResult? Function( IdentityEntry field0)?  identity,TResult? Function( CardEntry field0)?  card,TResult? Function( FileEntry field0)?  file,TResult? Function( CustomEntry field0)?  custom,}) {final _that = this;
switch (_that) {
case VaultEntry_Login() when login != null:
return login(_that.field0);case VaultEntry_Note() when note != null:
return note(_that.field0);case VaultEntry_Identity() when identity != null:
return identity(_that.field0);case VaultEntry_Card() when card != null:
return card(_that.field0);case VaultEntry_File() when file != null:
return file(_that.field0);case VaultEntry_Custom() when custom != null:
return custom(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class VaultEntry_Login extends VaultEntry {
  const VaultEntry_Login(this.field0): super._();
  

@override final  LoginEntry field0;

/// Create a copy of VaultEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VaultEntry_LoginCopyWith<VaultEntry_Login> get copyWith => _$VaultEntry_LoginCopyWithImpl<VaultEntry_Login>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VaultEntry_Login&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'VaultEntry.login(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $VaultEntry_LoginCopyWith<$Res> implements $VaultEntryCopyWith<$Res> {
  factory $VaultEntry_LoginCopyWith(VaultEntry_Login value, $Res Function(VaultEntry_Login) _then) = _$VaultEntry_LoginCopyWithImpl;
@useResult
$Res call({
 LoginEntry field0
});




}
/// @nodoc
class _$VaultEntry_LoginCopyWithImpl<$Res>
    implements $VaultEntry_LoginCopyWith<$Res> {
  _$VaultEntry_LoginCopyWithImpl(this._self, this._then);

  final VaultEntry_Login _self;
  final $Res Function(VaultEntry_Login) _then;

/// Create a copy of VaultEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(VaultEntry_Login(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as LoginEntry,
  ));
}


}

/// @nodoc


class VaultEntry_Note extends VaultEntry {
  const VaultEntry_Note(this.field0): super._();
  

@override final  NoteEntry field0;

/// Create a copy of VaultEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VaultEntry_NoteCopyWith<VaultEntry_Note> get copyWith => _$VaultEntry_NoteCopyWithImpl<VaultEntry_Note>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VaultEntry_Note&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'VaultEntry.note(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $VaultEntry_NoteCopyWith<$Res> implements $VaultEntryCopyWith<$Res> {
  factory $VaultEntry_NoteCopyWith(VaultEntry_Note value, $Res Function(VaultEntry_Note) _then) = _$VaultEntry_NoteCopyWithImpl;
@useResult
$Res call({
 NoteEntry field0
});




}
/// @nodoc
class _$VaultEntry_NoteCopyWithImpl<$Res>
    implements $VaultEntry_NoteCopyWith<$Res> {
  _$VaultEntry_NoteCopyWithImpl(this._self, this._then);

  final VaultEntry_Note _self;
  final $Res Function(VaultEntry_Note) _then;

/// Create a copy of VaultEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(VaultEntry_Note(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as NoteEntry,
  ));
}


}

/// @nodoc


class VaultEntry_Identity extends VaultEntry {
  const VaultEntry_Identity(this.field0): super._();
  

@override final  IdentityEntry field0;

/// Create a copy of VaultEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VaultEntry_IdentityCopyWith<VaultEntry_Identity> get copyWith => _$VaultEntry_IdentityCopyWithImpl<VaultEntry_Identity>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VaultEntry_Identity&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'VaultEntry.identity(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $VaultEntry_IdentityCopyWith<$Res> implements $VaultEntryCopyWith<$Res> {
  factory $VaultEntry_IdentityCopyWith(VaultEntry_Identity value, $Res Function(VaultEntry_Identity) _then) = _$VaultEntry_IdentityCopyWithImpl;
@useResult
$Res call({
 IdentityEntry field0
});




}
/// @nodoc
class _$VaultEntry_IdentityCopyWithImpl<$Res>
    implements $VaultEntry_IdentityCopyWith<$Res> {
  _$VaultEntry_IdentityCopyWithImpl(this._self, this._then);

  final VaultEntry_Identity _self;
  final $Res Function(VaultEntry_Identity) _then;

/// Create a copy of VaultEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(VaultEntry_Identity(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as IdentityEntry,
  ));
}


}

/// @nodoc


class VaultEntry_Card extends VaultEntry {
  const VaultEntry_Card(this.field0): super._();
  

@override final  CardEntry field0;

/// Create a copy of VaultEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VaultEntry_CardCopyWith<VaultEntry_Card> get copyWith => _$VaultEntry_CardCopyWithImpl<VaultEntry_Card>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VaultEntry_Card&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'VaultEntry.card(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $VaultEntry_CardCopyWith<$Res> implements $VaultEntryCopyWith<$Res> {
  factory $VaultEntry_CardCopyWith(VaultEntry_Card value, $Res Function(VaultEntry_Card) _then) = _$VaultEntry_CardCopyWithImpl;
@useResult
$Res call({
 CardEntry field0
});




}
/// @nodoc
class _$VaultEntry_CardCopyWithImpl<$Res>
    implements $VaultEntry_CardCopyWith<$Res> {
  _$VaultEntry_CardCopyWithImpl(this._self, this._then);

  final VaultEntry_Card _self;
  final $Res Function(VaultEntry_Card) _then;

/// Create a copy of VaultEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(VaultEntry_Card(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as CardEntry,
  ));
}


}

/// @nodoc


class VaultEntry_File extends VaultEntry {
  const VaultEntry_File(this.field0): super._();
  

@override final  FileEntry field0;

/// Create a copy of VaultEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VaultEntry_FileCopyWith<VaultEntry_File> get copyWith => _$VaultEntry_FileCopyWithImpl<VaultEntry_File>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VaultEntry_File&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'VaultEntry.file(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $VaultEntry_FileCopyWith<$Res> implements $VaultEntryCopyWith<$Res> {
  factory $VaultEntry_FileCopyWith(VaultEntry_File value, $Res Function(VaultEntry_File) _then) = _$VaultEntry_FileCopyWithImpl;
@useResult
$Res call({
 FileEntry field0
});




}
/// @nodoc
class _$VaultEntry_FileCopyWithImpl<$Res>
    implements $VaultEntry_FileCopyWith<$Res> {
  _$VaultEntry_FileCopyWithImpl(this._self, this._then);

  final VaultEntry_File _self;
  final $Res Function(VaultEntry_File) _then;

/// Create a copy of VaultEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(VaultEntry_File(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as FileEntry,
  ));
}


}

/// @nodoc


class VaultEntry_Custom extends VaultEntry {
  const VaultEntry_Custom(this.field0): super._();
  

@override final  CustomEntry field0;

/// Create a copy of VaultEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VaultEntry_CustomCopyWith<VaultEntry_Custom> get copyWith => _$VaultEntry_CustomCopyWithImpl<VaultEntry_Custom>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VaultEntry_Custom&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'VaultEntry.custom(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $VaultEntry_CustomCopyWith<$Res> implements $VaultEntryCopyWith<$Res> {
  factory $VaultEntry_CustomCopyWith(VaultEntry_Custom value, $Res Function(VaultEntry_Custom) _then) = _$VaultEntry_CustomCopyWithImpl;
@useResult
$Res call({
 CustomEntry field0
});




}
/// @nodoc
class _$VaultEntry_CustomCopyWithImpl<$Res>
    implements $VaultEntry_CustomCopyWith<$Res> {
  _$VaultEntry_CustomCopyWithImpl(this._self, this._then);

  final VaultEntry_Custom _self;
  final $Res Function(VaultEntry_Custom) _then;

/// Create a copy of VaultEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(VaultEntry_Custom(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as CustomEntry,
  ));
}


}

// dart format on
