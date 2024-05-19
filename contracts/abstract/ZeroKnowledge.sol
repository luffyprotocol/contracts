// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {UltraVerifier} from "../zk/plonk_vk.sol";


abstract contract ZeroKnowledge {
    UltraVerifier public zkVerifier; 

    constructor() 
    {
        zkVerifier=new UltraVerifier();
    }

    function _verifyProof(bytes memory _proof, bytes32[] memory _publicInputs) internal view returns(bool)
    {
         try zkVerifier.verify(_proof, _publicInputs)
        {
            return true;
        }catch{
            return false;
        }
    }


}