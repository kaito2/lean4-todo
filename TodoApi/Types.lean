namespace TodoApi

structure Todo where
  id : Nat
  title : String
  completed : Bool
  deriving Repr, BEq, Inhabited

end TodoApi
