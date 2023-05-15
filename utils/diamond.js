const ethers = require("ethers");

const FacetCutAction = { Add: 0, Replace: 1, Remove: 2 };

// used with getSelectors to remove selectors from an array of selectors
// functionNames argument is an array of function signatures
function remove(functionNames) {
  const selectors = this.filter((v) => {
    for (const functionName of functionNames) {
      if (v === this.contract.interface.getSighash(functionName)) {
        return false;
      }
    }
    return true;
  });
  selectors.contract = this.contract;
  selectors.remove = this.remove;
  selectors.get = this.get;
  return selectors;
}

// used with getSelectors to get selectors from an array of selectors
// functionNames argument is an array of function signatures
function get(functionNames) {
  const selectors = this.filter((v) => {
    for (const functionName of functionNames) {
      if (v === this.contract.interface.getSighash(functionName)) {
        return true;
      }
    }
    return false;
  });
  selectors.contract = this.contract;
  selectors.remove = this.remove;
  selectors.get = this.get;
  return selectors;
}

// remove selectors using an array of signatures
function removeSelectors(selectors, signatures) {
  const iface = new ethers.utils.Interface(signatures.map((v) => `function ${v}`));
  const _removeSelectors = signatures.map((v) => iface.getSighash(v));
  return selectors.filter((v) => !_removeSelectors.includes(v));
}

// find a particular address position in the return value of diamondLoupeFacet.facets()
function findAddressPositionInFacets(facetAddress, facets) {
  for (let i = 0; i < facets.length; i += 1) {
    if (facets[i].facetAddress === facetAddress) {
      return i;
    }
  }
  return -1;
}

// get function selectors from ABI
function getSelectors(contract) {
  const signatures = Object.keys(contract.methods);
  const selectors = signatures.reduce((acc, val) => {
    if (val !== "init(bytes)") {
      acc.push(ethers.utils.keccak256(ethers.utils.toUtf8Bytes(val)).slice(0, 10));
    }
    return acc;
  }, []);
  selectors.contract = contract;
  selectors.remove = remove;
  selectors.get = get;
  return selectors;
}

// get function selector from function signature
function getSelector(func) {
  const abiInterface = new ethers.utils.Interface([func]);
  return abiInterface.getSighash(ethers.utils.Fragment.from(func));
}

exports.getSelectors = getSelectors;
exports.getSelector = getSelector;
exports.FacetCutAction = FacetCutAction;
exports.remove = remove;
exports.removeSelectors = removeSelectors;
exports.findAddressPositionInFacets = findAddressPositionInFacets;
