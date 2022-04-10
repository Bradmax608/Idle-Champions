class _MemoryObjects
{
    class Reference
    {
        __new(offset32, offset64, parentObj)
        {
            this.Offset := MemoryReader.Reader.Is64Bit ? offset64 : offset32
            this.GetAddress := this.variableGetAddress
            this.ParentObj := parentObj
            return this
        }

        variableGetAddress()
        {
            return MemoryReader.Reader.read(this.ParentObj.GetAddress() + this.Offset, MemoryReader.Reader.ptrType)
        }

        SetAddress(setStatic)
        {
            if setStatic
            {
                this.Address := this.variableGetAddress()
                this.GetAddress := this.staticGetAddress
            }
            else
                this.GetAddress := this.variableGetAddress
        }

        staticGetAddress()
        {
            return this.Address
        }
    }

    class Collection extends _MemoryObjects.Reference
    {
        NewChild(parent, base, type, offset)
        {
            if (base.__Class == "_MemoryObjects.Value")
                obj := new base(0, 0, parent, type)
            else if (base.__Class == "_MemoryObjects.List")
                obj := new base(0, 0, parent, type.Base, type.Type)
            else if (base.__Class == "_MemoryObjects.Dictionary")
                obj := new base(0, 0, parent, base.Key, type.Key, base.Value, type.Value)
            else if (base.__Class == "_MemoryObjects.String")
                obj := new base(0, 0, parent)
            ;else if (base.isEnum == "_MemoryObjects.Enum")
            ;    obj := new base(0, 0, parent)
            else
                obj := new type(0, 0, parent)
            obj.Offset := offset
            return obj
        }
    }

    ;item base is the memory class, and item type is the c# type
    class List extends _MemoryObjects.Collection
    {
        __new(offset32, offset64, parentObject, itemBase, itemType)
        {
            this.Offset := MemoryReader.Reader.Is64Bit ? offset64 : offset32
            this.ParentObj := parentObject
            this.GetAddress := this.variableGetAddress
            this.List := new _MemoryObjects.Reference(offset32, offset64, parentObject)
            this._items := new _MemoryObjects.Reference(0x8, 0x10, this)
            this._size := new _MemoryObjects.Value(0xC, 0x18, this, "System.Int32")
            this.ItemOffsetBase := MemoryReader.Reader.Is64Bit ? 0x20 : 0x10
            this.ItemOffsetStep := MemoryReader.Reader.Is64Bit ? 0x8 : 0x4
            this.ItemBase := itemBase
            this.ItemType := itemType
            return this 
        }
        
        Size()
        {
            return this._size.GetValue()
        }

        GetItemOffset(index)
        {
            return this.ItemOffsetBase + (index * this.ItemOffsetStep)
        }

        Item[index]
        {
            get
            {
                return this.NewChild(this._items, this.ItemBase, this.ItemType, this.GetItemOffset(index))
            }
        }
    }

    class Dictionary extends _MemoryObjects.Collection
    {
        __new(offset32, offset64, parentObject, keyBase, keyType, valueBase, valueType)
        {
            this.Offset := MemoryReader.Reader.Is64Bit ? offset64 : offset32
            this.ParentObj := parentObject
            this.GetAddress := this.variableGetAddress
            this.Dict := new _MemoryObjects.Reference(offset32, offset64, parentObject)
            this.entries := new _MemoryObjects.Reference(0xC, 0x10, this)
            this.count := new _MemoryObjects.Value(0x20, 0x18, this, "System.Int32")
            this.KeyOffsetBase := MemoryReader.Reader.Is64Bit ? 0x28 : 0x18
            this.ValueOffsetBase := MemoryReader.Reader.Is64Bit ? 0x30 : 0x1C
            this.OffsetStep := MemoryReader.Reader.Is64Bit ? 0x18 : 0x10
            this.KeyBase := keyBase
            this.KeyType := keyType
            this.ValueBase := valueBase
            this.ValueType := valueType
            return this
        }

        Key[index]
        {
            get
            {
                return this.NewChild(this.entries, this.KeyBase, this.KeyType, this.GetKeyOffset(index))
            }
        }

        Value[index]
        {
            get
            {
                return this.NewChild(this.entries, this.ValueBase, this.ValueType, this.GetValueOffset(index))
            }
        }

        GetKeyOffset(index)
        {
            return this.KeyOffsetBase + (index * this.OffsetStep)
        }

        GetValueOffset(index)
        {
            return this.ValueOffsetBase + (index * this.OffsetStep)
        }
    }

    class Value
    {
        __new(offset32, offset64, parentObject, type)
        {
            this.Offset := MemoryReader.Reader.Is64Bit ? offset64 : offset32
            if !(_MemoryObjects.Value.genericTypeSize.HasKey(type))
                ExceptionHandler.ThrowError("Value type parameter is invalid.`nInvalid Parameter: " . type, -2)
            this.Type := type
            this.ParentObj := parentObject
            return this
        }

        GetValue()
        {
            return MemoryReader.Reader.read(this.ParentObj.GetAddress() + this.Offset, _MemoryObjects.Value.genericTypeSize[this.Type])
        }

        static genericTypeSize :=   {   "System.Byte": "Char",     "System.UByte": "UChar"
                                    ,   "System.Short": "Short",   "System.UShort": "UShort"
                                    ,   "System.Int32": "Int",     "System.UInt32": "UInt"
                                    ,   "System.Int64": "Int64",   "System.UInt64": "UInt64"
                                    ,   "System.Single": "Float",  "System.USingle": "UFloat"
                                    ,   "System.Double": "Double", "System.Boolean": "Char"}
    }

    class String extends _MemoryObjects.Reference
    {
        __new(offset32, offset64, parentObj)
        {
            this.Offset := MemoryReader.Reader.Is64Bit ? offset64 : offset32
            this.GetAddress := this.variableGetAddress
            this.ParentObj := parentObj
            this.Length := new _MemoryObjects.Value(0x8, 0x10, this, "System.Int32")
            this.Value := {}
            this.Value.Offset := MemoryReader.Reader.Is64Bit ? 0x14 : 0xC
            return this
        }

        GetValue()
        {
            baseAddress := this.GetAddress()
            return MemoryReader.Reader.readstring(baseAddress + this.Value.Offset, 0, "UTF-16")
        }
    }

    class Enum extends _MemoryObjects.Value
    {
        __new(offset32, offset64, parentObject)
        {
            this.isEnum := true ;this is hokey fix for tree view to differentiate enums from poiners, but I'm lazy right now.
            this.Offset := MemoryReader.Reader.Is64Bit ? offset64 : offset32
            if !(_MemoryObjects.Value.genericTypeSize.HasKey(this.Type))
                ExceptionHandler.ThrowError("Value type parameter is invalid.`nInvalid Parameter: " . this.Type, -2)
            this.ParentObj := parentObject
            return this
        }

        GetEnumerable()
        {
            return this.Enum[this.GetValue()]
        }
    }

    class StaticBase
    {
        GetAddress()
        {
            return MemoryReader.Reader.read(MemoryReader.ModuleBaseAddress + this.Offset, MemoryReader.Reader.ptrType)
        }
    }

    class EffectKey extends _MemoryObjects.Reference
    {
        __new()
        {
            this.Offset := 0
            this.GetAddress := this.variableGetAddress
            this.ParentObj := new _MemoryObjects.EffectKeyParent(new IdleGameManager, this.ChampID, this.UpgradeID, this.EffectID, this)
            return this
        }
        
        SetAddress(setStatic, address)
        {
            if setStatic
            {
                if setStatic
            {
                this.Address := address
                this.GetAddress := this.staticGetAddress
            }
            else
                this.GetAddress := this.variableGetAddress
            }
        }
    }

    class EffectKeyParent extends _MemoryObjects.Reference
    {
        __new(gameManager, champID, upgradeID, effectID, child)
        {
            this.Hero := gameManager.game.gameInstances.Item[0].HeroHandler.parent.heroes.Item[champID - 1]
            this.UpgradeID := upgradeID
            this.EffectID := effectID
            this.Child := child
            this.GetAddress := this.variableGetAddress
            return this
        }

        variableGetAddress()
        {
            ;will read hero's address once then reuse that address for subsequent reads. this should probably be applied at each loop.
            this.Hero.SetAddress(true)
            ;effectKeysByKeyName is Dict<string,List<CrusadersGame.Effects.EffectKey>>
            effectKeysByKeyName := this.Hero.effects.effectKeysByKeyName
            count := effectKeysByKeyname.count.GetValue()
            index := 0
            loop %count%
            {
                ;effectKeys is a list of EffectKey
                effectKeys := effectKeysByKeyName.Value[index]
                EK_size := effectKeys.Size()
                EK_index := 0
                loop %EK_size%
                {
                    if (effectKeys.Item[EK_index].parentEffectKeyHandler.parent.def.ID := this.EffectID)
                    {
                        ;activeEffecthandlers is list of CrusadersGame.Effects.ActiveEffectKeyHandler
                        ;these are the base type of our desired handlers, usually.
                        activeEffectHandlers := effectKeys.Item[EK_index].parentEffectKeyHandler.activeEffectHandlers
                        AEH_size := activeEffectHandlers.Size()
                        AEH_index := 0
                        loop %AEH_size%
                        {
                            ;this effect key isnt in active effect handlers need to pass in effect handler to get these
                            activeEffectHandlerAddress := activeEffectHandlers.Item[AEH_index].GetAddress()
                            this.Child.SetAddress(true, activeEffectHandlerAddress)
                            id := this.Child.effectKey.parentEffectKeyHandler.parent.def.ID.GetValue()
                            if (id == this.EffectID)
                            {
                                this.Hero.SetAddress(false)
                                this.Child.Offset := activeEffectHandlers.Item[AEH_index].Offset
                                return activeEffectHandlers._items.GetAddress()
                            }
                            ++AEH_index
                        }
                    }
                    ++EK_index
                }
                ++index
            }
            this.Hero.SetAddress(false)
            return ""
        }

        /* This version was the initial attempt to avoid string match, but can just do that with a dictionary of strings by ignoring te string, see above solution
        keeping for a while just in case some unique handler is introduced and this path is superior.
        variableGetAddressOLD()
        {
            ;will read hero's address once then reuse that address for subsequent reads. this should probably be applied at each loop.
            this.Hero.SetAddress(true)
            ;effectsByUPgradeID is Dict<int,List<CrusadersGame.Effects.Effect>>
            count := this.Hero.effectsByUpgradeId.count.GetValue()
            index := 0
            loop %count%
            {
                if (this.Hero.effectsByUpgradeId.Key[index].GetValue() == this.UpgradeID)
                    break
                ++index
            }
            Effect := this.Hero.effectsByUpgradeId.Value[index]
            _size := Effect.Size()
            listIndex := 0
            loop %_size%
            {
                ;effectKeyHandlers is list of CrusadersGame.Effects.EffectKeyHandler
                effectKeyHandlers := Effect.Item[listIndex].effectKeyHandlers
                ekh_size := effectKeyHandlers.Size()
                ekhIndex := 0
                loop %ekh_size%
                {
                    ;activeEffecthandlers is list of CrusadersGame.Effects.ActiveEffectKeyHandler
                    ;these are the base type of our desired handlers, usually.
                    activeEffectHandlers := effectKeyHandlers.Item[ekhIndex].activeEffectHandlers
                    aeh_size := activeEffectHandlers.Size()
                    AEH_index := 0
                    loop %aeh_size%
                    {
                        ;this effect key isnt in active effect handlers need to pass in effect handler to get these
                        activeEffectHandlerAddress := activeEffectHandlers.Item[AEH_index].GetAddress()
                        this.Child.SetAddress(true, activeEffectHandlerAddress)
                        id := this.Child.effectKey.parentEffectKeyHandler.parent.def.ID.GetValue()
                        if (id == this.EffectID)
                        {
                            this.Hero.SetAddress(false)
                            this.Child.Offset := activeEffectHandlers.Item[AEH_index].Offset
                            return activeEffectHandlers._items.GetAddress()
                        }
                        ++AEH_index
                    }
                    ++ekhIndex
                }
                ++listIndex
            }
            this.Hero.SetAddress(false)
            return ""
        }
        */
    }
}