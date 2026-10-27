-- Compatibility entry point. Build.lua owns the capsule UI and its bindings.
return require(script.Parent.Build)({BindingsOnly=true}).Capsules
