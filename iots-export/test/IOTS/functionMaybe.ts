// IOTSSpec.Slot
const Slot = t.type({
    getSlot: t.number
});

const MaybeFunctionArgA = t.union([
    Slot,
    t.null
]);

const MaybeFunctionArgReturn = t.string;

type MaybeFunction = (
    a: t.TypeOf<typeof MaybeFunctionArgA>
) => t.TypeOf<typeof MaybeFunctionArgReturn>;
