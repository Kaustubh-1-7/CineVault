import axios from "axios";
export const uploadToIpfs = async (file) => {
    if (file) {
      try {
        const fileData = new FormData();
        fileData.append("file", file);
        const res = await axios.post(
          "https://api.pinata.cloud/pinning/pinFileToIPFS",
          fileData,
          {
            headers: {
              pinata_api_key: "35cb1bf7be19d2a8fa0d",
              pinata_secret_api_key: "2c2e9e43bca7a619154cb48e8b060c5643ea6220d0b7c9deb565fa491b3b3a50",
              "Content-Type": "multipart/form-data",
            },
          }
        );
        const tokenURI = `https://ipfs.io/ipfs/${res.data.IpfsHash}`;
        console.log(tokenURI)
        return tokenURI;
      } catch (error) {
        console.error("Error uploading file:", error);
        throw new Error("Error uploading file to IPFS");
      }
    }
  };

  export const uploadToIpfsJson = async (jsonData) => {
    if(jsonData){
      try{
        const res = await axios.post('https://api.pinata.cloud/pinning/pinJSONToIPFS',jsonData,{
          headers:{
            pinata_api_key : '35cb1bf7be19d2a8fa0d',
            pinata_secret_api_key : '2c2e9e43bca7a619154cb48e8b060c5643ea6220d0b7c9deb565fa491b3b3a50',
            'Content-Type': 'application/json',
          }
        })
        const tokenURI = `https://ipfs.io/ipfs/${res.data.IpfsHash}`;
        console.log(tokenURI)
        return tokenURI;
      }
      catch(e){
        console.log("Error uploading JSON:", e)
        throw new Error("Error uploading JSON to IPFS")
      }
    }
  }

  export const getJsonFromIpfs = async (ipfsHash) => {
    if(ipfsHash){
      try{
        const res = await axios.get(ipfsHash);
        const jsonData = res.data;
        console.log(jsonData)
        return jsonData;
      }
      catch(e){
        console.log("Error fetching JSON:", e)
        throw new Error("Error fetching JSON from IPFS")
      }
    }
  }