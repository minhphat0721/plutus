"use strict";

module.exports = {
  purge: [],
  darkMode: false, // or 'media' or 'class'
  theme: {
    colors: {
      transparent: "transparent",
      current: "currentColor",
      black: "#283345",
      gray: "#eeeeee",
      darkgray: "#cbcbcb",
      white: "#ffffff",
      grayblue: "#f5f9fc",
      blue: "#4d48e1",
      lightblue: "#3688d5",
      red: "#de4c51",
      transgray: "rgba(10,10,10,0.4)",
    },
    boxShadow: {
      DEFAULT: "0 3px 6px 0 rgba(0, 0, 0, 0.21)"
    },
    extend: {
      gridTemplateRows: {
        main: "auto minmax(0, 1fr) auto",
        contractSetup: "auto auto minmax(0, 1fr)",
      },
      boxShadow: {
        deep: "0 2.5px 5px 0 rgba(0, 0, 0, 0.22)",
      },
    },
  },
  variants: {
    extend: {},
    backgroundColor: ["hover"],
    cursor: ["disabled", "hover"],
    opacity: ["disabled"],
  },
  plugins: [],
  corePlugins: {
    container: false,
    space: true,
    divideWidth: false,
    divideColor: false,
    divideStyle: false,
    divideOpacity: false,
    accessibility: false,
    appearance: false,
    backgroundAttachment: false,
    backgroundClip: false,
    backgroundColor: true,
    backgroundImage: true,
    gradientColorStops: true,
    backgroundOpacity: false,
    backgroundPosition: false,
    backgroundRepeat: false,
    backgroundSize: false,
    borderCollapse: false,
    borderColor: true,
    borderOpacity: false,
    borderRadius: true,
    borderStyle: false,
    borderWidth: true,
    boxSizing: false,
    cursor: true,
    display: true,
    flexDirection: true,
    flexWrap: false,
    placeItems: false,
    placeContent: false,
    placeSelf: false,
    alignItems: true,
    alignContent: false,
    alignSelf: false,
    justifyItems: false,
    justifyContent: true,
    justifySelf: false,
    flex: true,
    flexGrow: true,
    flexShrink: true,
    order: false,
    float: true,
    clear: false,
    fontFamily: false,
    fontWeight: true,
    height: true,
    lineHeight: true,
    listStylePosition: false,
    listStyleType: false,
    maxHeight: true,
    maxWidth: true,
    minHeight: false,
    minWidth: false,
    objectFit: false,
    objectPosition: false,
    opacity: true,
    outline: true,
    overflow: true,
    overscrollBehavior: false,
    placeholderColor: false,
    placeholderOpacity: false,
    pointerEvents: false,
    position: true,
    inset: true,
    resize: false,
    boxShadow: true,
    ringWidth: false,
    ringOffsetColor: false,
    ringOffsetWidth: false,
    ringColor: false,
    ringOpacity: false,
    fill: false,
    stroke: false,
    strokeWidth: false,
    tableLayout: false,
    textAlign: true,
    textOpacity: false,
    textOverflow: false,
    fontStyle: false,
    textTransform: true,
    textDecoration: false,
    fontSmoothing: false,
    fontVariantNumeric: false,
    letterSpacing: false,
    userSelect: false,
    verticalAlign: false,
    visibility: false,
    whitespace: false,
    wordBreak: false,
    width: true,
    zIndex: true,
    gap: true,
    gridAutoFlow: false,
    gridTemplateColumns: true,
    gridAutoColumns: false,
    gridColumn: false,
    gridColumnStart: false,
    gridColumnEnd: false,
    gridTemplateRows: true,
    gridAutoRows: false,
    gridRow: false,
    gridRowStart: false,
    gridRowEnd: false,
    transform: true,
    transformOrigin: false,
    scale: false,
    rotate: false,
    translate: true,
    skew: false,
    transitionProperty: true,
    transitionTimingFunction: false,
    transitionDuration: true,
    transitionDelay: false,
    animation: false,
  },
};
