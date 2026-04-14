// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'vault_bridge.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$VaultEntryData {

 Object get field0;



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VaultEntryData&&const DeepCollectionEquality().equals(other.field0, field0));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(field0));

@override
String toString() {
  return 'VaultEntryData(field0: $field0)';
}


}

/// @nodoc
class $VaultEntryDataCopyWith<$Res>  {
$VaultEntryDataCopyWith(VaultEntryData _, $Res Function(VaultEntryData) __);
}


/// Adds pattern-matching-related methods to [VaultEntryData].
extension VaultEntryDataPatterns on VaultEntryData {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( VaultEntryData_Login value)?  login,TResult Function( VaultEntryData_Note value)?  note,TResult Function( VaultEntryData_Identity value)?  identity,TResult Function( VaultEntryData_Card value)?  card,TResult Function( VaultEntryData_File value)?  file,TResult Function( VaultEntryData_Custom value)?  custom,required TResult orElse(),}){
final _that = this;
switch (_that) {
case VaultEntryData_Login() when login != null:
return login(_that);case VaultEntryData_Note() when note != null:
return note(_that);case VaultEntryData_Identity() when identity != null:
return identity(_that);case VaultEntryData_Card() when card != null:
return card(_that);case VaultEntryData_File() when file != null:
return file(_that);case VaultEntryData_Custom() when custom != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( VaultEntryData_Login value)  login,required TResult Function( VaultEntryData_Note value)  note,required TResult Function( VaultEntryData_Identity value)  identity,required TResult Function( VaultEntryData_Card value)  card,required TResult Function( VaultEntryData_File value)  file,required TResult Function( VaultEntryData_Custom value)  custom,}){
final _that = this;
switch (_that) {
case VaultEntryData_Login():
return login(_that);case VaultEntryData_Note():
return note(_that);case VaultEntryData_Identity():
return identity(_that);case VaultEntryData_Card():
return card(_that);case VaultEntryData_File():
return file(_that);case VaultEntryData_Custom():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( VaultEntryData_Login value)?  login,TResult? Function( VaultEntryData_Note value)?  note,TResult? Function( VaultEntryData_Identity value)?  identity,TResult? Function( VaultEntryData_Card value)?  card,TResult? Function( VaultEntryData_File value)?  file,TResult? Function( VaultEntryData_Custom value)?  custom,}){
final _that = this;
switch (_that) {
case VaultEntryData_Login() when login != null:
return login(_that);case VaultEntryData_Note() when note != null:
return note(_that);case VaultEntryData_Identity() when identity != null:
return identity(_that);case VaultEntryData_Card() when card != null:
return card(_that);case VaultEntryData_File() when file != null:
return file(_that);case VaultEntryData_Custom() when custom != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( LoginEntryData field0)?  login,TResult Function( NoteEntryData field0)?  note,TResult Function( IdentityEntryData field0)?  identity,TResult Function( CardEntryData field0)?  card,TResult Function( FileEntryData field0)?  file,TResult Function( CustomEntryData field0)?  custom,required TResult orElse(),}) {final _that = this;
switch (_that) {
case VaultEntryData_Login() when login != null:
return login(_that.field0);case VaultEntryData_Note() when note != null:
return note(_that.field0);case VaultEntryData_Identity() when identity != null:
return identity(_that.field0);case VaultEntryData_Card() when card != null:
return card(_that.field0);case VaultEntryData_File() when file != null:
return file(_that.field0);case VaultEntryData_Custom() when custom != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( LoginEntryData field0)  login,required TResult Function( NoteEntryData field0)  note,required TResult Function( IdentityEntryData field0)  identity,required TResult Function( CardEntryData field0)  card,required TResult Function( FileEntryData field0)  file,required TResult Function( CustomEntryData field0)  custom,}) {final _that = this;
switch (_that) {
case VaultEntryData_Login():
return login(_that.field0);case VaultEntryData_Note():
return note(_that.field0);case VaultEntryData_Identity():
return identity(_that.field0);case VaultEntryData_Card():
return card(_that.field0);case VaultEntryData_File():
return file(_that.field0);case VaultEntryData_Custom():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( LoginEntryData field0)?  login,TResult? Function( NoteEntryData field0)?  note,TResult? Function( IdentityEntryData field0)?  identity,TResult? Function( CardEntryData field0)?  card,TResult? Function( FileEntryData field0)?  file,TResult? Function( CustomEntryData field0)?  custom,}) {final _that = this;
switch (_that) {
case VaultEntryData_Login() when login != null:
return login(_that.field0);case VaultEntryData_Note() when note != null:
return note(_that.field0);case VaultEntryData_Identity() when identity != null:
return identity(_that.field0);case VaultEntryData_Card() when card != null:
return card(_that.field0);case VaultEntryData_File() when file != null:
return file(_that.field0);case VaultEntryData_Custom() when custom != null:
return custom(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class VaultEntryData_Login extends VaultEntryData {
  const VaultEntryData_Login(this.field0): super._();
  

@override final  LoginEntryData field0;

/// Create a copy of VaultEntryData
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VaultEntryData_LoginCopyWith<VaultEntryData_Login> get copyWith => _$VaultEntryData_LoginCopyWithImpl<VaultEntryData_Login>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VaultEntryData_Login&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'VaultEntryData.login(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $VaultEntryData_LoginCopyWith<$Res> implements $VaultEntryDataCopyWith<$Res> {
  factory $VaultEntryData_LoginCopyWith(VaultEntryData_Login value, $Res Function(VaultEntryData_Login) _then) = _$VaultEntryData_LoginCopyWithImpl;
@useResult
$Res call({
 LoginEntryData field0
});




}
/// @nodoc
class _$VaultEntryData_LoginCopyWithImpl<$Res>
    implements $VaultEntryData_LoginCopyWith<$Res> {
  _$VaultEntryData_LoginCopyWithImpl(this._self, this._then);

  final VaultEntryData_Login _self;
  final $Res Function(VaultEntryData_Login) _then;

/// Create a copy of VaultEntryData
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(VaultEntryData_Login(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as LoginEntryData,
  ));
}


}

/// @nodoc


class VaultEntryData_Note extends VaultEntryData {
  const VaultEntryData_Note(this.field0): super._();
  

@override final  NoteEntryData field0;

/// Create a copy of VaultEntryData
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VaultEntryData_NoteCopyWith<VaultEntryData_Note> get copyWith => _$VaultEntryData_NoteCopyWithImpl<VaultEntryData_Note>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VaultEntryData_Note&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'VaultEntryData.note(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $VaultEntryData_NoteCopyWith<$Res> implements $VaultEntryDataCopyWith<$Res> {
  factory $VaultEntryData_NoteCopyWith(VaultEntryData_Note value, $Res Function(VaultEntryData_Note) _then) = _$VaultEntryData_NoteCopyWithImpl;
@useResult
$Res call({
 NoteEntryData field0
});




}
/// @nodoc
class _$VaultEntryData_NoteCopyWithImpl<$Res>
    implements $VaultEntryData_NoteCopyWith<$Res> {
  _$VaultEntryData_NoteCopyWithImpl(this._self, this._then);

  final VaultEntryData_Note _self;
  final $Res Function(VaultEntryData_Note) _then;

/// Create a copy of VaultEntryData
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(VaultEntryData_Note(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as NoteEntryData,
  ));
}


}

/// @nodoc


class VaultEntryData_Identity extends VaultEntryData {
  const VaultEntryData_Identity(this.field0): super._();
  

@override final  IdentityEntryData field0;

/// Create a copy of VaultEntryData
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VaultEntryData_IdentityCopyWith<VaultEntryData_Identity> get copyWith => _$VaultEntryData_IdentityCopyWithImpl<VaultEntryData_Identity>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VaultEntryData_Identity&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'VaultEntryData.identity(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $VaultEntryData_IdentityCopyWith<$Res> implements $VaultEntryDataCopyWith<$Res> {
  factory $VaultEntryData_IdentityCopyWith(VaultEntryData_Identity value, $Res Function(VaultEntryData_Identity) _then) = _$VaultEntryData_IdentityCopyWithImpl;
@useResult
$Res call({
 IdentityEntryData field0
});




}
/// @nodoc
class _$VaultEntryData_IdentityCopyWithImpl<$Res>
    implements $VaultEntryData_IdentityCopyWith<$Res> {
  _$VaultEntryData_IdentityCopyWithImpl(this._self, this._then);

  final VaultEntryData_Identity _self;
  final $Res Function(VaultEntryData_Identity) _then;

/// Create a copy of VaultEntryData
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(VaultEntryData_Identity(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as IdentityEntryData,
  ));
}


}

/// @nodoc


class VaultEntryData_Card extends VaultEntryData {
  const VaultEntryData_Card(this.field0): super._();
  

@override final  CardEntryData field0;

/// Create a copy of VaultEntryData
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VaultEntryData_CardCopyWith<VaultEntryData_Card> get copyWith => _$VaultEntryData_CardCopyWithImpl<VaultEntryData_Card>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VaultEntryData_Card&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'VaultEntryData.card(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $VaultEntryData_CardCopyWith<$Res> implements $VaultEntryDataCopyWith<$Res> {
  factory $VaultEntryData_CardCopyWith(VaultEntryData_Card value, $Res Function(VaultEntryData_Card) _then) = _$VaultEntryData_CardCopyWithImpl;
@useResult
$Res call({
 CardEntryData field0
});




}
/// @nodoc
class _$VaultEntryData_CardCopyWithImpl<$Res>
    implements $VaultEntryData_CardCopyWith<$Res> {
  _$VaultEntryData_CardCopyWithImpl(this._self, this._then);

  final VaultEntryData_Card _self;
  final $Res Function(VaultEntryData_Card) _then;

/// Create a copy of VaultEntryData
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(VaultEntryData_Card(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as CardEntryData,
  ));
}


}

/// @nodoc


class VaultEntryData_File extends VaultEntryData {
  const VaultEntryData_File(this.field0): super._();
  

@override final  FileEntryData field0;

/// Create a copy of VaultEntryData
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VaultEntryData_FileCopyWith<VaultEntryData_File> get copyWith => _$VaultEntryData_FileCopyWithImpl<VaultEntryData_File>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VaultEntryData_File&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'VaultEntryData.file(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $VaultEntryData_FileCopyWith<$Res> implements $VaultEntryDataCopyWith<$Res> {
  factory $VaultEntryData_FileCopyWith(VaultEntryData_File value, $Res Function(VaultEntryData_File) _then) = _$VaultEntryData_FileCopyWithImpl;
@useResult
$Res call({
 FileEntryData field0
});




}
/// @nodoc
class _$VaultEntryData_FileCopyWithImpl<$Res>
    implements $VaultEntryData_FileCopyWith<$Res> {
  _$VaultEntryData_FileCopyWithImpl(this._self, this._then);

  final VaultEntryData_File _self;
  final $Res Function(VaultEntryData_File) _then;

/// Create a copy of VaultEntryData
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(VaultEntryData_File(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as FileEntryData,
  ));
}


}

/// @nodoc


class VaultEntryData_Custom extends VaultEntryData {
  const VaultEntryData_Custom(this.field0): super._();
  

@override final  CustomEntryData field0;

/// Create a copy of VaultEntryData
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VaultEntryData_CustomCopyWith<VaultEntryData_Custom> get copyWith => _$VaultEntryData_CustomCopyWithImpl<VaultEntryData_Custom>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VaultEntryData_Custom&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'VaultEntryData.custom(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $VaultEntryData_CustomCopyWith<$Res> implements $VaultEntryDataCopyWith<$Res> {
  factory $VaultEntryData_CustomCopyWith(VaultEntryData_Custom value, $Res Function(VaultEntryData_Custom) _then) = _$VaultEntryData_CustomCopyWithImpl;
@useResult
$Res call({
 CustomEntryData field0
});




}
/// @nodoc
class _$VaultEntryData_CustomCopyWithImpl<$Res>
    implements $VaultEntryData_CustomCopyWith<$Res> {
  _$VaultEntryData_CustomCopyWithImpl(this._self, this._then);

  final VaultEntryData_Custom _self;
  final $Res Function(VaultEntryData_Custom) _then;

/// Create a copy of VaultEntryData
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(VaultEntryData_Custom(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as CustomEntryData,
  ));
}


}

// dart format on
